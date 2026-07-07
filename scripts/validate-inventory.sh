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

# Required evidence must be resolved and attributable. A validation narrative is
# optional on leaf facts; source and verification status are not.
run_check structure "required top-level objects are missing" '
  (.schema_version|type=="string") and (.site.proxmox|type=="object") and
  (.site.network|type=="object") and (.capacity.policy|type=="object") and
  (.guests|type=="array" and length>0) and (.responsibilities|type=="array") and
  (.credentials|type=="array")'
run_check evidence "evidence records require value, status, and source" '
  [.. | objects | select(has("status")) |
    has("value") and (.status|IN("proposed","verified","blocked")) and
    (.source|type=="string" and length>0)] | all'
run_check unresolved "blocked or proposed required site facts remain" '
  ([.site.proxmox[], .site.network[]] | all(.status=="verified" and .value!=null))'

# Guest structure, identities, references, and resolved addressing.
run_check structure "every guest requires identity, ownership, resources, network, startup, and dependencies" '
  [.guests[] | (.id|type=="string" and length>0) and (.kind|IN("vm","lxc")) and
    (.owner|IN("opentofu","manual-existing")) and
    (.configuration_owner|IN("config-automation","manual-existing")) and
    (.depends_on|type=="array") and
    ([.resources.vcpu,.resources.memory_mib,.resources.disk_gib,.network.ipv4,.network.dns,.startup.order,.startup.delay_seconds] |
      all(type=="object" and has("value") and has("status") and has("source")))] | all'
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

# Credential descriptors are metadata, but credential values and unsafe material
# must never appear in inventory.
if ! jq -e '
  def secretkey: test("(^|_)(password|passwd|token|api[_-]?key|authorization|private[_-]?key|credential[_-]?value)($|_)";"i");
  def unsafe: test("BEGIN [A-Z ]*PRIVATE KEY|authorization[[:space:]]*:|bearer[[:space:]]+[A-Za-z0-9._~-]+|example\\.(com|org|net)|placeholder|changeme|todo";"i");
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
    ([.site.proxmox.storage_pools.value[]|((.total_gib|type)=="number" and .total_gib>0) and
      ((.existing_committed_gib|type)=="number" and .existing_committed_gib>=0) and
      ((.planned_gib|type)=="number" and .planned_gib>=0) and
      ((.resulting_headroom_percent|type)=="number") and
      (.existing_committed_gib + .planned_gib <= .total_gib)]|all)) and
  (.site.proxmox.measurement_timestamp.status=="verified" and
   (.site.proxmox.measurement_timestamp.value|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$")))'
run_check capacity "capacity policy requires verified operator approval and supported CPU mode" '
  (.capacity.policy.cpu.mode.value=="maximum_vcpu_overcommit_ratio") and
  (.capacity.policy.cpu.maximum_vcpu_overcommit_ratio.value|type=="number" and .>0) and
  (.capacity.policy.cpu.mode.status=="verified") and
  (.capacity.policy.cpu.maximum_vcpu_overcommit_ratio.status=="verified") and
  (.capacity.policy.cpu.approval_status.status=="verified") and
  (.capacity.policy.cpu.approval_status.value=="approved") and
  (.capacity.policy.minimum_memory_headroom_percent.status=="verified") and
  (.capacity.policy.minimum_memory_headroom_percent.value>=0 and .capacity.policy.minimum_memory_headroom_percent.value<100) and
  (.capacity.policy.minimum_storage_headroom_percent.status=="verified") and
  (.capacity.policy.minimum_storage_headroom_percent.value>=0 and .capacity.policy.minimum_storage_headroom_percent.value<100) and
  ([.guests[]|select(.owner=="opentofu")|.resources|.vcpu.value,.memory_mib.value,.disk_gib.value] | all(type=="number" and .>=0))'
run_check capacity "CPU policy threshold breached" '
  ((.site.proxmox.existing_committed_vcpu.value + ([.guests[]|select(.owner=="opentofu")|.resources.vcpu.value]|add)) /
    .site.proxmox.physical_threads.value) <= .capacity.policy.cpu.maximum_vcpu_overcommit_ratio.value'
run_check capacity "memory headroom threshold breached" '
  ((.site.proxmox.usable_memory_mib.value - (.site.proxmox.existing_committed_memory_mib.value +
    ([.guests[]|select(.owner=="opentofu")|.resources.memory_mib.value]|add))) * 100 /
    .site.proxmox.usable_memory_mib.value) >= .capacity.policy.minimum_memory_headroom_percent.value'
run_check capacity "storage headroom threshold breached" '
  .capacity.policy.minimum_storage_headroom_percent.value as $minimum |
  [.site.proxmox.storage_pools.value[] |
    ((.total_gib - .existing_committed_gib - .planned_gib) * 100 / .total_gib) >= $minimum] | all'
run_check capacity "recorded storage headroom is inconsistent with measured capacity" '
  [.site.proxmox.storage_pools.value[] |
    (((.total_gib - .existing_committed_gib - .planned_gib) * 100 / .total_gib) - .resulting_headroom_percent) |
      (if . < 0 then -. else . end) <= 0.1] | all'
run_check capacity "storage pool commitments differ from canonical totals" '
  ([.site.proxmox.storage_pools.value[].existing_committed_gib] | add) ==
    .site.proxmox.existing_committed_storage_gib.value and
  ([.site.proxmox.storage_pools.value[].planned_gib] | add) ==
    ([.guests[] | select(.owner=="opentofu") | .resources.disk_gib.value] | add)'

# Exact approved topology: three new guests and one retained observation.
run_check topology "new guest set must be exactly postgres-01, services-01, and k3s-01" '
  ([.guests[]|select(.owner=="opentofu")|.id]|sort)==["k3s-01","postgres-01","services-01"]'
run_check topology "fixed guest identities, allocations, and startup values differ from approval" '
  def exact($id;$kind;$gid;$vcpu;$mem;$disk;$ip;$dns;$order;$delay):
    [.guests[]|select(.id==$id and .kind==$kind and .guest_id.value==$gid and
      .resources.vcpu.value==$vcpu and .resources.memory_mib.value==$mem and .resources.disk_gib.value==$disk and
      .network.ipv4.value==$ip and .network.dns.value==$dns and
      .startup.order.value==$order and .startup.delay_seconds.value==$delay)]|length==1;
  exact("postgres-01";"lxc";120;2;4096;64;"10.10.30.100";"postgres.app.kayage.co";10;30) and
  exact("services-01";"vm";121;4;8192;64;"10.10.30.101";"services.app.kayage.co";20;30) and
  exact("k3s-01";"vm";122;4;8192;64;"10.10.30.102";"k3s.app.kayage.co";40;30)'
run_check topology "planned allocation must total 10 vCPU, 20480 MiB RAM, and 192 GiB disk" '
  ([.guests[]|select(.owner=="opentofu")|.resources.vcpu.value]|add)==10 and
  ([.guests[]|select(.owner=="opentofu")|.resources.memory_mib.value]|add)==20480 and
  ([.guests[]|select(.owner=="opentofu")|.resources.disk_gib.value]|add)==192'
run_check topology "Docker Compose is allowed only on services-01 VM" '
  ([.guests[]|select(.runtime?=="docker-compose")]|length)==1 and
  ([.guests[]|select(.runtime?=="docker-compose" and .id=="services-01" and .kind=="vm")]|length)==1 and
  ([.guests[]|select(.kind=="lxc" and (.runtime?=="docker-compose" or has("services")))]|length)==0'
run_check services "services-01 must contain exactly Valkey, NATS/JetStream, and Debezium with readiness metadata" '
  .guests[]|select(.id=="services-01") |
  ([.services[].id]|sort)==["debezium","nats","valkey"] and
  ([.services[]|(.depends_on|type=="array") and (.readiness|type=="string" and length>0)]|all) and
  ([.services[]|select(.id=="nats" and .mode=="jetstream")]|length)==1 and
  ([.services[]|select(.id=="debezium")|.depends_on|sort]==[["nats","postgres-01"]]) and
  (.service_readiness_contract|type=="string" and length>0)'
run_check dependency "k3s dependencies must match the approved guest/service boundary" '
  [.guests[]|select(.id=="k3s-01")|.depends_on|sort]==[["postgres-01","services-01","zitadel-existing"]]'
run_check zitadel-existing "retained Zitadel observation is incomplete or not verified" '
  [.guests[]|select(.id=="zitadel-existing" and .owner=="manual-existing" and .configuration_owner=="manual-existing" and
    .observed_guest_id.status=="verified" and .observed_guest_id.value!=null and
    ([.resources.vcpu,.resources.memory_mib,.resources.disk_gib,.network.ipv4,.network.dns,
       .startup.order,.startup.delay_seconds,.measurement_source,.measurement_timestamp] |
      all(.status=="verified" and .value!=null)))]|length==1'
run_check ownership "Argo CD ownership must be limited to Kubernetes resources" '
  ([.responsibilities[]|select((.owner|ascii_downcase)=="argocd")]|length==1) and
  ([.responsibilities[]|select((.owner|ascii_downcase)=="argocd")|
    (.capability=="kubernetes-resources" and (.boundary|test("inside k3s only") and test("never guests")))]|all) and
  ([.guests[]|select(.owner=="argocd" or .configuration_owner=="argocd")]|length==0)'
run_check credentials "credential descriptors are incomplete or expose values" '
  [.credentials[] | [.system,.logical_name,.secret_store_label,.owner,.minimum_scope,.verification_status,.consumers] |
    all(.!=null and (((type=="string") and length>0) or ((type=="array") and length>0)))] | all'

if ((${#errors[@]})); then
  printf 'ERROR %s\n' "${errors[@]}" >&2
  exit 1
fi
echo "Inventory validation passed"
