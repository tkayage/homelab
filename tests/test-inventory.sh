#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp "$root/infrastructure/inventory.json" "$tmp/valid.json"
"$root/scripts/validate-inventory.sh" "$tmp/valid.json" >/dev/null

assert_mutation_rejected() {
  local fixture=$1 category=$2 filter
  filter=$(jq -er '.filter' "$root/tests/fixtures/$fixture")
  jq "$filter" "$tmp/valid.json" >"$tmp/invalid.json"
  if "$root/scripts/validate-inventory.sh" "$tmp/invalid.json" >"$tmp/out" 2>&1; then
    echo "FAIL: $fixture was accepted" >&2; exit 1
  fi
  grep -qi "$category" "$tmp/out" || {
    echo "FAIL: $fixture did not report diagnostic category $category" >&2
    cat "$tmp/out" >&2; exit 1
  }
}

assert_inline_rejected() {
  local name=$1 category=$2 filter=$3
  jq "$filter" "$tmp/valid.json" >"$tmp/invalid.json"
  if "$root/scripts/validate-inventory.sh" "$tmp/invalid.json" >"$tmp/out" 2>&1; then
    echo "FAIL: $name was accepted" >&2; exit 1
  fi
  grep -qi "$category" "$tmp/out" || {
    echo "FAIL: $name did not report diagnostic category $category" >&2
    cat "$tmp/out" >&2; exit 1
  }
}

assert_mutation_rejected invalid-duplicate-ip.json identity
assert_mutation_rejected invalid-secret-field.json secret-safety
assert_mutation_rejected invalid-capacity.json capacity
assert_mutation_rejected invalid-unresolved.json unresolved

assert_inline_rejected legacy-per-service-guest topology \
  '.guests += [{"id":"valkey-01","kind":"lxc","owner":"opentofu","configuration_owner":"config-automation","depends_on":[],"resources":.guests[0].resources,"network":.guests[0].network,"startup":.guests[0].startup}]'
assert_inline_rejected missing-compose-service services \
  '(.guests[]|select(.id=="services-01")|.services) |= map(select(.id!="nats"))'
assert_inline_rejected docker-in-lxc topology \
  '(.guests[]|select(.id=="services-01")|.kind)="lxc"'
assert_inline_rejected wrong-fixed-allocation topology \
  '(.guests[]|select(.id=="services-01")|.resources.memory_mib.value)=4096'
assert_inline_rejected broken-guest-dependency dependency \
  '(.guests[]|select(.id=="k3s-01")|.depends_on)+=["missing-guest"]'
assert_inline_rejected broken-compose-dependency services \
  '(.guests[]|select(.id=="services-01")|.services[]|select(.id=="debezium")|.depends_on)=["postgres-01"]'
assert_inline_rejected missing-compose-readiness services \
  'del(.guests[]|select(.id=="services-01")|.services[]|select(.id=="valkey")|.readiness)'
assert_inline_rejected storage-claim-inconsistent capacity \
  '(.site.proxmox.storage_pools.value[0].resulting_headroom_percent) += 1'
assert_inline_rejected storage-derived-breach capacity \
  '(.site.proxmox.storage_pools.value[0].total_gib) = 600'
assert_inline_rejected storage-missing-measured-total capacity \
  'del(.site.proxmox.storage_pools.value[0].total_gib)'

echo "Inventory validator tests passed"
