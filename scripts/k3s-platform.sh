#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf_dir="$root/infrastructure/opentofu/k3s"
local_dir="$root/.local"
kubeconfig="$local_dir/kubeconfig-k3s-01"
credentials=${HOMELAB_PROXMOX_ENV:-/home/tonny/.config/homelab/proxmox.env}
ssh_host=10.10.30.102
ssh_user=ubuntu
ssh_key=${K3S_SSH_KEY:-$HOME/.ssh/id_rsa}

fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "dependency missing: $1"; }

load_environment() {
  need tofu; need jq; need curl; need ssh; need kubectl; need openssl
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
  api /storage/local | jq -e '.data.content | split(",") | index("snippets") != null' >/dev/null || fail "local storage does not allow snippets"
  local existing
  existing=$(api /cluster/resources?type=vm | jq -r '.data[] | select(.vmid==122) | .name')
  [[ -z "$existing" || "$existing" == k3s-01 ]] || fail "VMID 122 is occupied by an undeclared guest"
  printf 'Preflight passed\n'
}

apply_cluster() {
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

fetch_kubeconfig() {
  wait_ssh
  umask 077
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" 'sudo cat /etc/rancher/k3s/k3s.yaml' |
    sed "s#https://127.0.0.1:6443#https://${ssh_host}:6443#" >"$kubeconfig"
  chmod 600 "$kubeconfig"
}

validate_cluster() {
  load_environment
  fetch_kubeconfig
  export KUBECONFIG="$kubeconfig"
  kubectl wait --for=condition=Ready node/k3s-01 --timeout=300s
  kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s
  kubectl rollout status deployment/traefik -n kube-system --timeout=300s
  [[ $(kubectl get node k3s-01 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') == "$ssh_host" ]]
  [[ $(kubectl get pvc -A --no-headers 2>/dev/null | awk '$1 != "kube-system" {count++} END {print count+0}') == 0 ]]
  ssh -i "$ssh_key" -o BatchMode=yes "$ssh_user@$ssh_host" 'sudo k3s --version; systemctl is-active --quiet k3s qemu-guest-agent'
  printf 'Live cluster validation passed\n'
}

destroy_cluster() {
  load_environment
  tofu -chdir="$tf_dir" destroy -input=false -auto-approve
  rm -f "$kubeconfig"
  ssh-keygen -R "$ssh_host" >/dev/null 2>&1 || true
}

replace_cluster() { destroy_cluster; apply_cluster; validate_cluster; }

case ${1:-} in
  preflight) preflight ;;
  apply) apply_cluster ;;
  validate) validate_cluster ;;
  destroy) destroy_cluster ;;
  replace) replace_cluster ;;
  *) fail "usage: $0 {preflight|apply|validate|destroy|replace}" ;;
esac
