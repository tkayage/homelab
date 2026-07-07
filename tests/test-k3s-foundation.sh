#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tf="$root/infrastructure/opentofu/k3s/main.tf"
cloud="$root/infrastructure/opentofu/k3s/cloud-init.yaml.tftpl"

static_checks() {
  tofu -chdir="$root/infrastructure/opentofu/k3s" fmt -check
  rg -q 'version = "= 0.111.0"' "$tf"
  rg -q 'vm_id\s+= 122' "$tf"
  rg -q 'cores = 4' "$tf" && rg -q 'dedicated = 8192' "$tf" && rg -q 'size\s+= 64' "$tf"
  rg -q '10.10.30.102/24' "$tf" && rg -q 'bridge = "vmbr0"' "$tf"
  rg -q 'v1.34.9\+k3s1' "$tf" && rg -q '80eebb578e36a04c' "$tf"
  rg -q 'enforced = true' "$tf"
  rg -q 'write-kubeconfig-mode: "0600"' "$cloud"
  ! rg -qi 'local-path.*application|hostPath:' "$cloud"
  git -C "$root" check-ignore -q .local/kubeconfig-k3s-01
  git -C "$root" check-ignore -q infrastructure/opentofu/k3s/terraform.tfstate
  bash -n "$root/scripts/k3s-platform.sh"
  printf 'Static k3s foundation tests passed\n'
}

case ${1:-static} in
  static) static_checks ;;
  live) static_checks; "$root/scripts/k3s-platform.sh" validate ;;
  *) printf 'usage: %s {static|live}\n' "$0" >&2; exit 2 ;;
esac
