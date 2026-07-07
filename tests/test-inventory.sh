#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Resolve a safe acceptance inventory from the canonical contract in temporary data.
jq '
  def verify: .status="verified";
  (.site.proxmox[] |= verify) | (.site.network[] |= verify) |
  .site.proxmox.version.value="8.4" | .site.proxmox.node.value="MS-01" |
  .site.proxmox.physical_cores.value=32 | .site.proxmox.physical_threads.value=64 |
  .site.proxmox.usable_memory_mib.value=131072 |
  .site.proxmox.storage_pools.value=[{"name":"local-zfs","usable_gib":2000,"free_gib":1800}] |
  .site.proxmox.existing_committed_vcpu.value=0 |
  .site.proxmox.existing_committed_memory_mib.value=0 |
  .site.proxmox.existing_committed_storage_gib.value=0 |
  .site.proxmox.measurement_timestamp.value="2026-07-07T12:00:00Z" |
  .site.network.bridge.value="vmbr0" | .site.network.vlan.value="untagged" |
  .site.network.subnet.value="10.10.0.0/24" | .site.network.gateway.value="10.10.0.1" |
  .site.network.dns_suffix.value="home.arpa" |
  .site.network.dhcp_exclusion_static_range.value="10.10.0.10-10.10.0.99" |
  .site.network.npm_identity.value="npm.home.arpa (10.10.0.5)" |
  (.capacity.policy.cpu[] |= verify) | .capacity.policy.cpu.approval_status.value="approved" |
  (.capacity.policy.minimum_memory_headroom_percent |= verify) |
  (.capacity.policy.minimum_storage_headroom_percent |= verify) |
  .guests |= (to_entries | map(.key as $k | .value |
    .network.ipv4.value=("10.10.0."+(($k+10)|tostring)) |
    .network.dns.value=(.id+".home.arpa"))) |
  (.guests[] | .resources[], .network[], .startup[]) |= (.status="verified") |
  (.guests[] | select(.id=="zitadel-existing")) |= (
    .observed_guest_id.value=105 | .observed_guest_id.status="verified" |
    .resources.vcpu.value=2 | .resources.memory_mib.value=4096 | .resources.disk_gib.value=32 |
    .startup.order.value=5 | .startup.delay_seconds.value=30 |
    .measurement_source.value="Proxmox read-only inventory" | .measurement_source.status="verified" |
    .measurement_timestamp.value="2026-07-07T12:00:00Z" | .measurement_timestamp.status="verified")
' "$root/infrastructure/inventory.json" >"$tmp/valid.json"

"$root/scripts/validate-inventory.sh" "$tmp/valid.json" >/dev/null

assert_rejected() {
  local fixture=$1 category=$2
  if "$root/scripts/validate-inventory.sh" "$root/tests/fixtures/$fixture" >"$tmp/out" 2>&1; then
    echo "FAIL: $fixture was accepted" >&2
    exit 1
  fi
  if ! grep -qi "$category" "$tmp/out"; then
    echo "FAIL: $fixture did not report diagnostic category $category" >&2
    exit 1
  fi
}

assert_rejected invalid-duplicate-ip.json identity
assert_rejected invalid-secret-field.json secret-safety
assert_rejected invalid-capacity.json capacity
assert_rejected invalid-unresolved.json zitadel-existing

echo "Inventory validator tests passed"
