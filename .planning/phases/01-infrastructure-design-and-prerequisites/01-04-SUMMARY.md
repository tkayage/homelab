---
phase: 01-infrastructure-design-and-prerequisites
plan: 04
subsystem: infrastructure
tags: [proxmox, capacity, topology, access-evidence, zitadel]
requires:
  - phase: 01-infrastructure-design-and-prerequisites
    provides: Inventory validation and secret-safe prerequisite procedures from plans 01-02 and 01-03
provides:
  - Operator-approved three-guest topology
  - Source-dated Proxmox, network, Zitadel, namespace, and access evidence
  - Explicit record of measurements still blocked from finalization
affects: [01-05, phase-02, phase-03, phase-04, phase-05, provisioning]
tech-stack:
  added: []
  patterns: [secret-free-evidence-record, observe-only-existing-systems, compose-service-consolidation]
key-files:
  created: [.planning/phases/01-infrastructure-design-and-prerequisites/01-04-SUMMARY.md]
  modified: []
key-decisions:
  - "Provision exactly three new guests: native PostgreSQL LXC, supporting-services Compose VM, and disposable k3s VM."
  - "Apply a maximum vCPU/thread ratio of 2.5 and minimum RAM and storage reserves of 20%."
  - "Keep existing Zitadel, NPM, Cloudflared, and Frigate LXCs separate and observe-only; no additional LXC is justified."
patterns-established:
  - "Valkey, NATS/JetStream, and Debezium share services-01 and use Compose health/readiness ordering."
  - "Credential evidence contains only secret-store labels and redacted access outcomes."
requirements-completed: [INFRA-03]
coverage:
  - id: D1
    description: "Operator-approved topology and capacity policies are recorded with source-dated evidence."
    requirement: "INFRA-03"
    verification:
      - kind: manual_procedural
        ref: "Operator approval and read-only environment inspection on 2026-07-07"
        status: pass
    human_judgment: true
    rationale: "Target-system facts and architecture approval cannot be independently established from repository automation."
duration: 5min
completed: 2026-07-07
status: complete
---

# Phase 1 Plan 4: Environment Evidence and Topology Approval Summary

**Secret-free evidence records the approved three-guest platform topology and identifies the remaining measurements without inference**

## Performance

- **Started:** 2026-07-07T14:34:12Z
- **Completed:** 2026-07-07T14:39:12Z
- **Tasks:** 1
- **Files modified:** 1

## Approved topology

Approved by the operator on `2026-07-07`.

| Inventory identity | Kind | VMID | IPv4 | DNS | vCPU | Memory | Disk | Startup |
|---|---|---:|---|---|---:|---:|---:|---|
| `guests.postgres-01` | LXC | 120 | `10.10.30.100` | `postgres.app.kayage.co` | 2 | 4096 MiB | 64 GiB | order 10, delay 30 seconds |
| `guests.services-01` | VM | 121 | `10.10.30.101` | `services.app.kayage.co` | 4 | 8192 MiB | 64 GiB | order 20, delay 30 seconds |
| `guests.k3s-01` | VM | 122 | `10.10.30.102` | `k3s.app.kayage.co` | 4 | 8192 MiB | 64 GiB | order 40, delay 30 seconds |

`postgres-01` runs native PostgreSQL. `services-01` runs Valkey, NATS with JetStream, and Debezium in one Docker Compose project; service dependency, health, and readiness ordering are internal to Compose. Docker-in-LXC remains prohibited. `k3s-01` remains ephemeral and disposable.

Existing Zitadel, NPM, Cloudflared, and Frigate remain separate existing LXCs. Their established isolation or hardware/network role justifies retaining them, but no additional new dedicated LXC is justified for this milestone.

## Capacity policy approvals

| Canonical inventory path | Approved value | Approver | Date | Evidence/status |
|---|---|---|---|---|
| `capacity.policy.cpu.maximum_vcpu_overcommit_ratio` | 2.5 vCPU per physical thread | operator | 2026-07-07 | approved; measured host basis is 20 threads |
| `capacity.policy.minimum_memory_headroom_percent` | 20% | operator | 2026-07-07 | approved; 94.0338 GiB physical RAM, 49.5 GiB existing allocation, and 20 GiB proposed allocation leave 24.5338 GiB (26.1%) |
| `capacity.policy.minimum_storage_headroom_percent` | 20% | operator | 2026-07-07 | policy approved; capacity proof blocked pending usable-pool and committed-storage measurements |
| `guests[].resources` | Exact sizes in the approved topology table | operator | 2026-07-07 | approved |

CPU acceptance cannot yet be recalculated from canonical commitments because `site.proxmox.existing_committed_vcpu` was not supplied. The previously reported aggregate post-change ratio was approximately 2.0, below the approved 2.5 maximum, but this report does not infer an exact existing commitment from that rounded result.

## Site and network evidence

Evidence was consolidated at `2026-07-07T14:39:12Z` from read-only Proxmox and RouterOS API observations made during the operator-assisted session.

| Canonical inventory path | Observed value | Status | Evidence source |
|---|---|---|---|
| `site.proxmox.version` | `PVE 8.4.19` | verified | Proxmox PVEAuditor API metadata |
| `site.proxmox.node` | `proxmox` | verified | Proxmox node API listing |
| `site.proxmox.physical_cores` | 14 | verified | Proxmox node status/CPU topology observation |
| `site.proxmox.physical_threads` | 20 | verified | Proxmox node status/CPU topology observation |
| `site.proxmox.usable_memory_mib` | approximately 96290.6 MiB (94.0338 GiB) physical RAM | verified | Proxmox node status API |
| `site.proxmox.existing_committed_memory_mib` | 50688 MiB (49.5 GiB) | verified | Proxmox guest inventory after removals |
| `site.proxmox.existing_committed_vcpu` | not supplied | blocked | Exact configured-vCPU total must be retained from a fresh guest inventory |
| `site.proxmox.storage_pools` | not supplied | blocked | Usable target-pool capacities must be retained from Proxmox storage status |
| `site.proxmox.existing_committed_storage_gib` | not supplied | blocked | Existing provisioned volume total must be measured |
| `site.proxmox.measurement_timestamp` | `2026-07-07T14:39:12Z` evidence-consolidation time | verified | Operator clock; source observations occurred in the same session |
| `site.network.bridge` | `vmbr0` | verified | Proxmox network observation |
| `site.network.vlan` | not supplied | blocked | Tagged or explicitly untagged mode must be confirmed |
| `site.network.subnet` | `10.10.30.0/24` | verified | Proxmox and RouterOS network observation |
| `site.network.gateway` | `10.10.30.1` | verified | RouterOS address observation |
| `site.network.dns_suffix` | `app.kayage.co` | verified | Operator-approved host assignments and active Cloudflare zone |
| `site.network.dhcp_exclusion_static_range` | `10.10.30.100-10.10.30.200`; candidates `.100-.104` returned no response when checked | verified for selected addresses | RouterOS state and collision probes |
| `site.network.npm_identity` | IPv4 `10.10.30.237`; stable DNS name not supplied | partially blocked | NPM API and LAN reachability observation |

## Existing Zitadel observation

Zitadel remains `manual-existing` and observe-only. No resize, renumber, restart, or configuration change is authorized.

| Canonical inventory path | Observed value | Status | Evidence source | Timestamp |
|---|---|---|---|---|
| `guests.zitadel-existing.observed_guest_id` | 112 | verified | Proxmox PVEAuditor guest inventory | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.resources.vcpu` | 1 | verified | Read-only LXC configuration | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.resources.memory_mib` | 1024 MiB | verified | Read-only LXC configuration | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.resources.disk_gib` | 8 GiB | verified | Read-only LXC configuration | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.network.ipv4` | `10.10.30.236` | verified | Read-only LXC and LAN observation | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.network.dns` | hostname `zitadel`; resolvable FQDN not supplied | partially blocked | Read-only LXC configuration | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.startup.order` | no explicit startup field observed | blocked | Read-only LXC configuration; absence is not interpreted as an order | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.startup.delay_seconds` | no explicit startup field observed | blocked | Read-only LXC configuration; absence is not interpreted as a delay | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.measurement_source` | Proxmox PVEAuditor API guest list and LXC configuration | verified | Redacted read-only request metadata | 2026-07-07T14:39:12Z |
| `guests.zitadel-existing.measurement_timestamp` | `2026-07-07T14:39:12Z` | verified | Operator clock; evidence consolidation | 2026-07-07T14:39:12Z |

The guest has `onboot=1`; this confirms automatic startup is enabled but does not establish an explicit order or delay.

## External namespace and package evidence

| Fact | Outcome | Evidence source | Timestamp |
|---|---|---|---|
| Cloudflare zones | `kayage.co` and `hapa.dev` are active | Cloudflare zone metadata API | 2026-07-07T14:39:12Z |
| GitHub repository | private `tkayage/gitops-homelab`, default branch `main`, accessible | GitHub repository metadata API | 2026-07-07T14:39:12Z |
| GHCR package ownership/access | owner `tkayage`; package-read check succeeded and one package was visible | GitHub Packages API, redacted result | 2026-07-07T14:39:12Z |

## Access verification

Only descriptor labels and non-secret outcomes are recorded. No password, token, key, cookie, authorization header, session, or recovery code is present.

| System | Secret-store label | Outcome | Non-secret evidence source | Timestamp |
|---|---|---|---|---|
| Proxmox | `homelab/proxmox/opentofu` | PASS: PVEAuditor API authentication and target inventory reads succeeded | Redacted Proxmox role and request status | 2026-07-07T14:39:12Z |
| Mikrotik LAN | `homelab/mikrotik/lan-automation` | PASS: authenticated REST reads succeeded on RouterOS 7.23.1 | Redacted RouterOS request status | 2026-07-07T14:39:12Z |
| NPM | `homelab/npm/platform-automation` | PASS: authenticated API at `10.10.30.237` enumerated 10 proxy hosts | Redacted NPM request status | 2026-07-07T14:39:12Z |
| Cloudflare | `homelab/cloudflare/platform-zone` | PASS: both approved zones returned active metadata | Redacted Cloudflare zone request status | 2026-07-07T14:39:12Z |
| GitHub | `homelab/github/gitops-automation` | PASS: private repository metadata and `main` were readable | Redacted GitHub repository request status | 2026-07-07T14:39:12Z |
| GHCR | `homelab/ghcr/cluster-pull` | PASS: package-read access succeeded | Redacted package-list request status | 2026-07-07T14:39:12Z |

These checks establish the requested read paths. They do not prove every descriptor's future mutation scope; least-privilege write/deny checks remain a finalization concern where the current temporary identities are read-only.

## Decisions Made

- Approved the exact three-guest topology above.
- Approved the 2.5 maximum vCPU/thread ratio and 20% RAM/storage reserves.
- Consolidated Valkey, NATS/JetStream, and Debezium into `services-01` while preserving PostgreSQL as a native dedicated LXC.
- Retained existing Zitadel, NPM, Cloudflared, and Frigate LXCs without creating new per-service LXCs.

## Task Commits

1. **Task 1: Confirm collected evidence and approved three-guest topology** - committed with this summary (`docs`)

## Files Created/Modified

- `.planning/phases/01-infrastructure-design-and-prerequisites/01-04-SUMMARY.md` - Auditable operator decisions, observed facts, access outcomes, and explicit evidence gaps.

## Deviations from Plan

None - plan executed exactly as written. Missing measurements are marked blocked as required rather than inferred.

## Issues Encountered

- Storage capacity and commitment measurements were not included in the collected evidence, so the approved 20% storage reserve cannot yet pass its numeric gate.
- Exact existing vCPU commitment, VLAN mode, NPM DNS name, Zitadel FQDN, and explicit Zitadel startup order/delay were not supplied.

## User Setup Required

None for this evidence-recording plan. Plan 01-05 must resolve the blocked measurements before authorizing provisioning.

## Next Phase Readiness

- Plan 01-05 can migrate the approved three-guest topology without preserving obsolete per-service guest assumptions.
- Finalization must retain fresh storage, vCPU, VLAN, NPM DNS, and Zitadel DNS/startup evidence or keep provisioning blocked.

## Self-Check: PASSED

- The required summary exists and covers topology, approvals, site/network facts, Zitadel, namespaces, and all six access systems.
- A secret-pattern review found no authentication material.
- Every absent required measurement is explicitly marked blocked.

---
*Phase: 01-infrastructure-design-and-prerequisites*
*Completed: 2026-07-07*
