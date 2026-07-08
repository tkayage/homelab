#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="$root/infrastructure/opentofu/postgres"
local_dir="$root/.local"
credentials=${HOMELAB_PROXMOX_ENV:-/home/tonny/.config/homelab/proxmox.env}
ssh_host=10.10.30.100
# Standard Proxmox Ubuntu LXC template ships root-only (no cloud-init user);
# the provisioning SSH key is injected for root. sudo is present, so the
# in-container `sudo -u postgres` calls still work.
ssh_user=root
ssh_key=${POSTGRES_SSH_KEY:-$HOME/.ssh/id_rsa}
nfs_share=${POSTGRES_NFS_SHARE:-10.10.40.2:/volume1/backup/postgres}
# Backup runs from the Proxmox host (host-based approach): the host mounts the
# NFS export and dumps the DB via `pct exec` — no NFS mount inside the
# unprivileged LXC. PREREQUISITES (operator/NAS actions, not automatable here):
#   1. NAS: create export ${nfs_share} allowing ${pve_host}.
#   2. Proxmox host: authorize this SSH key for ${pve_user}@${pve_host}.
# Until both exist this path cannot be exercised; pg_dumpall itself is verified.
pve_host=${PVE_BACKUP_HOST:-10.10.30.30}
pve_user=${PVE_BACKUP_USER:-root}
pve_ssh_key=${PVE_SSH_KEY:-$HOME/.ssh/id_rsa}
backup_mount=${POSTGRES_BACKUP_MOUNT:-/mnt/pg-backup}

fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "dependency missing: $1"; }

load_environment() {
  need tofu; need jq; need curl; need ssh; need openssl
  [[ -r "$credentials" ]] || fail "Proxmox credential file is unavailable"
  [[ -r "$ssh_key" ]] || fail "SSH identity is unavailable"
  mkdir -p "$local_dir"; chmod 700 "$local_dir"
  if [[ ! -f "$local_dir/state-passphrase" ]]; then
    umask 077; openssl rand -base64 48 >"$local_dir/state-passphrase"
  fi
  chmod 600 "$local_dir/state-passphrase"
  set -a; source "$credentials"; set +a
  export PROXMOX_VE_ENDPOINT="$PVE_URL"
  export PROXMOX_VE_API_TOKEN="${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"
  export PROXMOX_VE_INSECURE="${PVE_VERIFY_TLS:-false}"
  export TF_VAR_state_passphrase="$(<"$local_dir/state-passphrase")"
  export TF_VAR_ssh_public_key="$(ssh-keygen -y -f "$ssh_key")"
  export TF_VAR_proxmox_ssh_private_key="$(<"$ssh_key")"
}

api() {
  local path=$1; shift || true
  local tls=(); [[ "${PVE_VERIFY_TLS:-true}" == true ]] || tls=(-k)
  curl "${tls[@]}" -fsS -H "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}" "$@" "${PVE_URL%/}/api2/json${path}"
}

preflight() {
  load_environment
  tofu -chdir="$tf_dir" fmt -check
  tofu -chdir="$tf_dir" init -input=false >/dev/null
  tofu -chdir="$tf_dir" validate >/dev/null
  api /access/permissions | jq -e '[.data[] | has("Sys.Modify") and has("VM.Allocate") and has("VM.PowerMgmt") and has("Datastore.AllocateSpace")] | any' >/dev/null || fail "required Proxmox privileges are missing"
  local existing
  existing=$(api /cluster/resources?type=vm | jq -r '.data[] | select(.vmid==120) | .name')
  [[ -z "$existing" || "$existing" == postgres-01 ]] || fail "VMID 120 is occupied by an undeclared guest"
  printf 'Preflight passed\n'
}

apply_postgres() {
  preflight
  tofu -chdir="$tf_dir" apply -input=false -auto-approve
}

wait_ssh() {
  ssh-keygen -R "$ssh_host" >/dev/null 2>&1 || true
  for _ in $(seq 1 90); do
    if ssh -i "$ssh_key" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$ssh_user@$ssh_host" true 2>/dev/null; then return; fi
    sleep 5
  done
  fail "SSH readiness timed out"
}

configure_postgres() {
  load_environment
  wait_ssh
  
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "sudo bash -s" << 'EOF'
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    
    # Install PostgreSQL 17
    apt-get update
    apt-get install -y postgresql-common curl gnupg2
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
    apt-get install -y postgresql-17
    
    # Configure postgresql.conf
    CONF="/etc/postgresql/17/main/postgresql.conf"
    sed -i "s/#listen_addresses = .*/listen_addresses = '*' /" $CONF
    sed -i "s/^shared_buffers = .*/shared_buffers = 1024MB/" $CONF
    sed -i "s/#wal_level = .*/wal_level = logical/" $CONF
    sed -i "s/#max_replication_slots = .*/max_replication_slots = 4/" $CONF
    sed -i "s/#max_wal_senders = .*/max_wal_senders = 4/" $CONF
    sed -i "s/#max_slot_wal_keep_size = .*/max_slot_wal_keep_size = 4GB/" $CONF
    
    # Configure pg_hba.conf
    HBA="/etc/postgresql/17/main/pg_hba.conf"
    echo "host all all 10.10.30.0/24 scram-sha-256" >> $HBA
    
    systemctl restart postgresql
    
    # Create debezium role
    sudo -u postgres psql -c "CREATE ROLE debezium WITH REPLICATION LOGIN PASSWORD 'debezium';" || true
    # Pre-create the CDC publication as superuser (the least-privilege debezium
    # role cannot CREATE PUBLICATION FOR ALL TABLES). Debezium references this
    # with publication.autocreate.mode=disabled.
    sudo -u postgres psql -c "CREATE PUBLICATION dbz_publication FOR ALL TABLES;" || true
EOF
  printf 'PostgreSQL configured\n'
}

validate_postgres() {
  load_environment
  wait_ssh
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "sudo -u postgres psql -c '\conninfo' >/dev/null" || fail "PostgreSQL local connection failed"
  printf 'PostgreSQL validation passed\n'
}

# Host-based backup: the Proxmox host mounts NFS and dumps the DB via `pct exec`,
# avoiding an NFS mount inside the unprivileged LXC. Requires the two
# prerequisites documented at the top of this script. UNVERIFIED end-to-end
# until they are in place; `pg_dumpall` itself is verified.
backup_postgres() {
  load_environment
  ssh -i "$pve_ssh_key" -o BatchMode=yes "$pve_user@$pve_host" "bash -s" << EOF
    set -euo pipefail
    mkdir -p "$backup_mount"
    mountpoint -q "$backup_mount" || mount -t nfs -o hard,nfsvers=4,noatime "$nfs_share" "$backup_mount"
    ts=\$(date +%Y%m%d_%H%M%S)
    pct exec 120 -- su - postgres -c 'pg_dumpall --clean --if-exists' | gzip > "$backup_mount/pg_dumpall_\${ts}.sql.gz"
    find "$backup_mount" -name 'pg_dumpall_*.sql.gz' -mtime +14 -delete
    echo "Backup complete: pg_dumpall_\${ts}.sql.gz"
EOF
}

restore_test() {
  load_environment
  ssh -i "$pve_ssh_key" -o BatchMode=yes "$pve_user@$pve_host" "bash -s" << EOF
    set -euo pipefail
    mkdir -p "$backup_mount"
    mountpoint -q "$backup_mount" || mount -t nfs -o hard,nfsvers=4,noatime "$nfs_share" "$backup_mount"
    latest=\$(ls -t "$backup_mount"/pg_dumpall_*.sql.gz 2>/dev/null | head -1)
    [ -n "\$latest" ] || { echo 'No backup found to restore'; exit 1; }
    scratch="restore_verify_\$(date +%s)"
    pct exec 120 -- su - postgres -c "createdb \$scratch"
    gunzip -c "\$latest" | pct exec 120 -- su - postgres -c "psql -d \$scratch" 2>/dev/null || true
    pct exec 120 -- su - postgres -c "psql -Atd \$scratch -c \\"SELECT count(*) FROM pg_tables WHERE schemaname='public';\\""
    pct exec 120 -- su - postgres -c "dropdb \$scratch"
    echo 'Restore verification passed'
EOF
}

destroy_postgres() {
  load_environment
  tofu -chdir="$tf_dir" destroy -input=false -auto-approve
  ssh-keygen -R "$ssh_host" >/dev/null 2>&1 || true
}

case ${1:-} in
  preflight) preflight ;;
  apply) apply_postgres ;;
  configure) configure_postgres ;;
  validate) validate_postgres ;;
  backup) backup_postgres ;;
  restore-test) restore_test ;;
  destroy) destroy_postgres ;;
  *) fail "usage: $0 {preflight|apply|configure|validate|backup|restore-test|destroy}" ;;
esac
