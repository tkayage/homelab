#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="$root/infrastructure/opentofu/services"
local_dir="$root/.local"
credentials=${HOMELAB_PROXMOX_ENV:-/home/tonny/.config/homelab/proxmox.env}
ssh_host=10.10.30.101
ssh_user=ubuntu
ssh_key=${SERVICES_SSH_KEY:-$HOME/.ssh/id_rsa}

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
  api /storage/local | jq -e '.data.content | split(",") | (index("snippets") != null and index("import") != null)' >/dev/null || fail "local storage does not allow snippets and import content"
  local existing
  existing=$(api /cluster/resources?type=vm | jq -r '.data[] | select(.vmid==121) | .name')
  [[ -z "$existing" || "$existing" == services-01 ]] || fail "VMID 121 is occupied by an undeclared guest"
  printf 'Preflight passed\n'
}

apply_services() {
  preflight
  tofu -chdir="$tf_dir" apply -input=false -auto-approve
}

deploy_services() {
  load_environment
  
  # /opt is root-owned; create the tree and hand it to the deploy user so the
  # unprivileged scp below can write. The .env (holding the Debezium DB
  # password) is created out-of-band by the operator and preserved here.
  ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new "${ssh_user}@${ssh_host}" "sudo mkdir -p /opt/homelab/services/debezium && sudo chown -R ${ssh_user}:${ssh_user} /opt/homelab"
  scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new -r "$root/infrastructure/services/"* "${ssh_user}@${ssh_host}:/opt/homelab/services/"
  
  ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new "${ssh_user}@${ssh_host}" "test -f /opt/homelab/services/.env" || fail "/opt/homelab/services/.env does not exist on remote host"
  
  ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new "${ssh_user}@${ssh_host}" "cd /opt/homelab/services && sudo docker compose up -d"
}

validate_services() {
  load_environment

  local running_count
  running_count=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new "${ssh_user}@${ssh_host}" "cd /opt/homelab/services && sudo docker compose ps --status running --format '{{.State}}'" | grep -c '^running$' || true)
  
  if [[ "$running_count" -lt 3 ]]; then
    fail "Not all Docker containers are running on remote host"
  fi
  
  ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new "${ssh_user}@${ssh_host}" "sudo docker exec \$(sudo docker compose -f /opt/homelab/services/docker-compose.yaml ps -q valkey) valkey-cli ping | grep -q PONG" || fail "Valkey is not healthy"
  
  printf 'Services are healthy\n'
}

destroy_services() {
  load_environment
  tofu -chdir="$tf_dir" destroy -input=false -auto-approve
  ssh-keygen -R "$ssh_host" >/dev/null 2>&1 || true
}

case ${1:-} in
  preflight) preflight ;;
  apply) apply_services ;;
  deploy) deploy_services ;;
  validate) validate_services ;;
  destroy) destroy_services ;;
  *) echo "usage: $0 {preflight|apply|deploy|validate|destroy}" ;;
esac
