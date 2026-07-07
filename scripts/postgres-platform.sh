#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="$root/infrastructure/opentofu/postgres"
local_dir="$root/.local"
credentials=${HOMELAB_PROXMOX_ENV:-/home/tonny/.config/homelab/proxmox.env}
ssh_host=10.10.30.100
ssh_user=ubuntu
ssh_key=${POSTGRES_SSH_KEY:-$HOME/.ssh/id_rsa}
nfs_share=${POSTGRES_NFS_SHARE:-10.10.40.2:/volume1/backup/postgres}

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
  existing=$(api /cluster/resources?type=lxc | jq -r '.data[] | select(.vmid==120) | .name')
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
EOF
  printf 'PostgreSQL configured\n'
}

validate_postgres() {
  load_environment
  wait_ssh
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "sudo -u postgres psql -c '\conninfo' >/dev/null" || fail "PostgreSQL local connection failed"
  printf 'PostgreSQL validation passed\n'
}

backup_postgres() {
  load_environment
  wait_ssh
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "sudo bash -s" << EOF
    set -euo pipefail
    apt-get update && apt-get install -y nfs-common
    mkdir -p /mnt/backup
    if ! mountpoint -q /mnt/backup; then
      mount -t nfs -o hard,nfsvers=4,noatime $nfs_share /mnt/backup
    fi
    TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
    RETENTION_DAYS=14
    sudo -u postgres pg_dumpall --clean --if-exists | gzip > "/mnt/backup/pg_dumpall_\${TIMESTAMP}.sql.gz"
    find /mnt/backup -name "pg_dumpall_*.sql.gz" -mtime +\${RETENTION_DAYS} -delete
    echo "Backup complete: pg_dumpall_\${TIMESTAMP}.sql.gz"
EOF
}

restore_test() {
  load_environment
  wait_ssh
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "sudo bash -s" << EOF
    set -euo pipefail
    apt-get update && apt-get install -y nfs-common
    mkdir -p /mnt/backup
    if ! mountpoint -q /mnt/backup; then
      mount -t nfs -o hard,nfsvers=4,noatime $nfs_share /mnt/backup
    fi
    LATEST=\$(ls -t /mnt/backup/pg_dumpall_*.sql.gz | head -1)
    [ -n "\$LATEST" ] || { echo "No backup found to restore"; exit 1; }
    SCRATCH_DB="restore_verify_\$(date +%s)"
    sudo -u postgres psql -c "CREATE DATABASE \${SCRATCH_DB};"
    gunzip -c "\$LATEST" | sudo -u postgres psql -d "\$SCRATCH_DB" 2>/dev/null || true
    sudo -u postgres psql -d "\$SCRATCH_DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
    sudo -u postgres psql -c "DROP DATABASE \${SCRATCH_DB};"
    echo "Restore verification passed"
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
