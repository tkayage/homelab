#!/usr/bin/env bash
set -euo pipefail

inventory=${1:-infrastructure/inventory.json}
errors=()
fail() { errors+=("$1"); }

command -v jq >/dev/null 2>&1 || { echo "ERROR dependency: jq is required" >&2; exit 2; }
[[ -r "$inventory" ]] || { echo "ERROR input: inventory is not readable: $inventory" >&2; exit 2; }
jq -e . "$inventory" >/dev/null 2>&1 || { echo "ERROR structure: inventory is not valid JSON" >&2; exit 1; }

run_check() {
  local category=$1 message=$2 expression=$3
  jq -e "$expression" "$inventory" >/dev/null 2>&1 || fail "$category: $message"
}

# Evidence objects and final-gate resolution.
run_check structure "required top-level objects are missing" '
  (.schema_version|type=="string") and (.site|type=="object") and
  (.site.proxmox|type=="object") and (.site.network|type=="object") and
  (.capacity.policy|type=="object") and (.guests|type=="array" and length>0) and
  (.responsibilities|type=="array") and (.credentials|type=="array")'
run_check evidence "evidence records require value, status, validation, and source" '
  [.. | objects | select(has("status")) |
    has("value") and (.status|IN("proposed","verified","blocked")) and
    (.validation|type=="string" and length>0) and (.source|type=="string" and length>0)] | all'
run_check unresolved "blocked or proposed required site facts remain" '
  ([.site.proxmox[], .site.network[]] | all(.status=="verified" and .value!=null))'

# Guest structure, identities, references, and resolved addressing.
run_check structure "every guest requires identity, ownership, resources, network, startup, and dependencies" '
  [.guests[] | (.id|type=="string" and length>0) and (.kind|IN("vm","lxc")) and
    (.owner|IN("opentofu","manual-existing")) and
    (.configuration_owner|IN("config-automation","manual-existing")) and
    (.depends_on|type=="array") and
    ([.resources.vcpu,.resources.memory_mib,.resources.disk_gib,.network.ipv4,.network.dns,.startup.order,.startup.delay_seconds] |
      all(type=="object" and has("value") and has("status") and has("validation") and has("source")))] | all'
run_check identity "guest IDs must be unique" '(.guests|map(.id)|length)==(.guests|map(.id)|unique|length)'
run_check identity "guest IPv4 addresses must be non-null and unique" '
  (.guests|map(.network.ipv4.value)|all(.!=null and type=="string")) and
  ((.guests|map(.network.ipv4.value)|length)==(.guests|map(.network.ipv4.value)|unique|length))'
run_check identity "guest DNS names must be non-null and unique" '
  (.guests|map(.network.dns.value)|all(.!=null and type=="string" and length>0)) and
  ((.guests|map(.network.dns.value)|length)==(.guests|map(.network.dns.value)|unique|length))'
run_check dependency "guest dependency IDs must resolve" '
  (.guests|map(.id)) as $ids | [.guests[].depends_on[]] | all(. as $d | $ids|index($d)!=null)'
run_check startup "dependent guests must start after every dependency" '
  (.guests|map({key:.id,value:.startup.order.value})|from_entries) as $orders |
  [.guests[] | . as $g | $g.depends_on[] | ($orders[$g.id] > $orders[.])] | all'

# Secret-shaped keys and values are rejected without reproducing values in diagnostics.
if ! jq -e '
  def secretkey: test("(^|_)(secret|password|passwd|token|api[_-]?key|authorization|private[_-]?key|credential[_-]?value)($|_)";"i");
  def unsafe: test("BEGIN [A-Z ]*PRIVATE KEY|authorization[[:space:]]*:|bearer[[:space:]]+[A-Za-z0-9._~-]+|example\\.(com|org|net)|placeholder|changeme|todo|^[A-Za-z0-9+/=_-]{48,}$";"i");
  ([paths(objects) as $p | (getpath($p)|keys[]) | select(secretkey)]|length==0) and
  ([.. | strings | select(unsafe)]|length==0)' "$inventory" >/dev/null 2>&1; then
  fail "secret-safety: credential-shaped key or unsafe/placeholder material detected (value suppressed)"
fi

# Capacity inputs, approvals, and arithmetic.
run_check capacity "host capacity measurements require verified numeric values, source, and RFC3339 timestamp" '
  ([.site.proxmox.physical_threads,.site.proxmox.usable_memory_mib,
     .site.proxmox.existing_committed_vcpu,.site.proxmox.existing_committed_memory_mib,
     .site.proxmox.existing_committed_storage_gib] | all(.status=="verified" and (.value|type=="number") and .value>=0 and (.source|length>0))) and
  (.site.proxmox.storage_pools.status=="verified" and (.site.proxmox.storage_pools.value|type=="array" and length>0) and
    [.site.proxmox.storage_pools.value[]|(.usable_gib|type=="number") and (.free_gib|type=="number")]|all) and
  (.site.proxmox.measurement_timestamp.status=="verified" and
   (.site.proxmox.measurement_timestamp.value|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$")))'
run_check capacity "capacity policy requires verified operator approval and supported CPU mode" '
  (.capacity.policy.cpu.mode.value|IN("minimum_uncommitted_thread_percent","maximum_vcpu_overcommit_ratio")) and
  (.capacity.policy.cpu.threshold.value|type=="number" and .>0) and
  (.capacity.policy.cpu.mode.status=="verified") and (.capacity.policy.cpu.threshold.status=="verified") and
  (.capacity.policy.cpu.approval_status.status=="verified") and
  (.capacity.policy.cpu.approval_status.value=="approved") and
  (.capacity.policy.cpu.approval_status.source|type=="string" and length>0) and
  (.capacity.policy.minimum_memory_headroom_percent.status=="verified") and
  (.capacity.policy.minimum_memory_headroom_percent.value>=0 and .capacity.policy.minimum_memory_headroom_percent.value<100) and
  (.capacity.policy.minimum_storage_headroom_percent.status=="verified") and
  (.capacity.policy.minimum_storage_headroom_percent.value>=0 and .capacity.policy.minimum_storage_headroom_percent.value<100) and
  ([.guests[].resources | .vcpu.value,.memory_mib.value,.disk_gib.value] | all(type=="number" and .>=0))'
if jq -e '.site.proxmox.physical_threads.value|numbers' "$inventory" >/dev/null 2>&1; then
  cpu_ok=$(jq -r '
    ([.guests[].resources.vcpu.value]|add) + .site.proxmox.existing_committed_vcpu.value as $used |
    .site.proxmox.physical_threads.value as $threads | .capacity.policy.cpu as $p |
    if $p.mode.value=="minimum_uncommitted_thread_percent" then
      ((($threads-$used)*100/$threads) >= $p.threshold.value)
    elif $p.mode.value=="maximum_vcpu_overcommit_ratio" then
      (($used/$threads) <= $p.threshold.value)
    else false end' "$inventory" 2>/dev/null || echo false)
  [[ $cpu_ok == true ]] || fail "capacity: CPU policy threshold breached"
fi
run_check capacity "memory headroom threshold breached" '
  ((.site.proxmox.usable_memory_mib.value - (.site.proxmox.existing_committed_memory_mib.value + ([.guests[].resources.memory_mib.value]|add))) * 100 /
    .site.proxmox.usable_memory_mib.value) >= .capacity.policy.minimum_memory_headroom_percent.value'
run_check capacity "storage headroom threshold breached" '
  (.site.proxmox.storage_pools.value|map(.usable_gib)|add) as $usable |
  (($usable - (.site.proxmox.existing_committed_storage_gib.value + ([.guests[].resources.disk_gib.value]|add))) * 100 / $usable) >=
    .capacity.policy.minimum_storage_headroom_percent.value'

# Fixed topology and ownership boundaries.
run_check topology "exactly one disposable k3s VM is required" '
  ([.guests[]|select(.kind=="vm" and .data_class=="ephemeral-disposable" and .id=="k3s-01")]|length)==1'
run_check topology "Postgres, Valkey, NATS, and Debezium must be native-service LXCs" '
  (["postgres-01","valkey-01","nats-01","debezium-01"] as $required |
   [.guests[]|select(.id as $id|$required|index($id))|select(.kind=="lxc")]|length)==4'
run_check zitadel-existing "retained Zitadel observation is incomplete or not verified" '
  .guests[]|select(.id=="zitadel-existing") |
  .owner=="manual-existing" and .configuration_owner=="manual-existing" and
  ([.observed_guest_id,.resources.vcpu,.resources.memory_mib,.resources.disk_gib,.network.ipv4,.network.dns,
     .startup.order,.startup.delay_seconds,.measurement_source,.measurement_timestamp] |
    all(.status=="verified" and .value!=null))'
run_check ownership "Argo CD ownership must be limited to Kubernetes resources" '
  ([.responsibilities[]|select((.owner|ascii_downcase)=="argocd")]|length==1) and
  ([.responsibilities[]|select((.owner|ascii_downcase)=="argocd")|
    (.capability=="kubernetes-resources" and (.boundary|test("inside k3s only") and test("never guests")))]|all) and
  ([.guests[]|select(.owner=="argocd" or .configuration_owner=="argocd")]|length==0)'
run_check credentials "credential descriptors are incomplete or exceed clear minimum-scope descriptions" '
  [.credentials[] | [.system,.logical_name,.owner,.minimum_scope,.storage_location,.consumers,.rotation_revocation,.acquisition_verification] |
    all(.!=null and ((type=="string" and length>=8) or (type=="array" and length>0)))] | all'

if ((${#errors[@]})); then
  printf 'ERROR %s\n' "${errors[@]}" >&2
  exit 1
fi
echo "Inventory validation passed"
