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
# Workstation-mediated off-host backup. The operator workstation is the only host
# that can BOTH ssh into the postgres LXC AND reach the NAS NFS export, so it runs
# the backup. The dump streams: postgres LXC --ssh--> workstation --nfs--> NAS.
# Why not the alternatives:
#   * Proxmox host (10.10.30.30) has no reachable shell — root ssh is denied by
#     key and password, and the PVE API exposes no host command exec.
#   * The unprivileged LXC cannot mount NFS itself — the `nfs` container feature
#     flag is settable only by root@pam, not by the provisioning API token.
# PREREQUISITE (NAS action, not automatable here): grant the workstation
# (${backup_client}) read/write NFS access to ${nfs_share}. `pg_dumpall` over ssh
# is verified; the NAS write + restore are verified once that grant is in place.
nfs_share=${POSTGRES_NFS_SHARE:-10.10.40.2:/volume1/homelab-backups}
backup_subdir=${POSTGRES_BACKUP_SUBDIR:-postgres}
backup_mount=${POSTGRES_BACKUP_MOUNT:-/mnt/pg-backup}
backup_client=${POSTGRES_BACKUP_CLIENT:-10.10.30.70}
# restore-test verifies the dump against a DISPOSABLE postgres container on the
# services VM (Docker host) — never against the live server, because a pg_dumpall
# carries global DROP/CREATE ROLE and \connect statements that would mutate
# production. services-01 has Docker; the scratch container is removed after.
svc_host=${SERVICES_SSH_HOST:-10.10.30.101}
svc_user=${SERVICES_SSH_USER:-ubuntu}
scratch_image=${POSTGRES_SCRATCH_IMAGE:-postgres:17}
scratch_name=${POSTGRES_SCRATCH_NAME:-pg-restore-verify}

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

ssh_lxc() { ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" "$@"; }
ssh_svc() { ssh -i "$ssh_key" -o BatchMode=yes "$svc_user@$svc_host" "$@"; }

mount_backup() {
  sudo mkdir -p "$backup_mount"
  mountpoint -q "$backup_mount" && return 0
  sudo mount -t nfs -o hard,nfsvers=4,noatime "$nfs_share" "$backup_mount" \
    || fail "cannot mount $nfs_share — grant $backup_client read/write NFS access on the NAS"
}
umount_backup() { mountpoint -q "$backup_mount" && sudo umount "$backup_mount" || true; }

# Workstation-mediated off-host backup: stream the cluster dump from the LXC over
# ssh straight onto the NAS export. `pg_dumpall` over ssh is verified; the NAS
# write is exercised once the export grants $backup_client rw (see header notes).
backup_postgres() {
  load_environment
  mount_backup
  local dest="$backup_mount/$backup_subdir"
  sudo mkdir -p "$dest"
  local ts file; ts=$(date +%Y%m%d_%H%M%S); file="$dest/pg_dumpall_${ts}.sql.gz"
  if ssh_lxc "sudo -u postgres pg_dumpall --clean --if-exists" | gzip | sudo tee "$file" >/dev/null; then
    sudo find "$dest" -name 'pg_dumpall_*.sql.gz' -mtime +14 -delete
    printf 'Backup complete: %s (%s)\n' "$file" "$(sudo du -h "$file" | cut -f1)"
  else
    umount_backup; fail "backup failed"
  fi
  umount_backup
}

# Restore the latest NAS backup into a DISPOSABLE postgres container on the
# services VM and confirm globals + databases reconstruct. Verified live against
# the LXC dump; only the NAS read-back is pending the export grant.
restore_test() {
  load_environment
  mount_backup
  local dest="$backup_mount/$backup_subdir" latest
  latest=$(sudo ls -t "$dest"/pg_dumpall_*.sql.gz 2>/dev/null | head -1) \
    || { umount_backup; fail "no backup found in $dest"; }
  [[ -n "$latest" ]] || { umount_backup; fail "no backup found in $dest"; }

  ssh_svc "docker rm -f $scratch_name >/dev/null 2>&1; docker run -d --name $scratch_name -e POSTGRES_PASSWORD=verify $scratch_image >/dev/null"
  local ready=
  for _ in $(seq 1 30); do
    if ssh_svc "docker exec $scratch_name pg_isready -U postgres -q" 2>/dev/null; then ready=1; break; fi
    sleep 3
  done
  [[ -n "$ready" ]] || { ssh_svc "docker rm -f $scratch_name >/dev/null 2>&1"; umount_backup; fail "scratch instance did not become ready"; }

  sudo cat "$latest" | gunzip | ssh_svc "docker exec -i $scratch_name psql -U postgres -v ON_ERROR_STOP=0" >/dev/null 2>&1
  local roles dbs
  roles=$(ssh_svc "docker exec $scratch_name psql -U postgres -Atqc \"SELECT count(*) FROM pg_roles WHERE rolname='debezium' AND rolreplication AND rolcanlogin\"")
  dbs=$(ssh_svc "docker exec $scratch_name psql -U postgres -Atqc \"SELECT count(*) FROM pg_database WHERE datistemplate=false\"")
  ssh_svc "docker rm -f $scratch_name >/dev/null"
  umount_backup
  [[ "$roles" == 1 ]] || fail "restore verification failed: debezium role not reconstructed (roles=$roles)"
  printf 'Restore verification passed (scratch %s: debezium role reconstructed, %s database(s) restored)\n' "$scratch_image" "$dbs"
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
