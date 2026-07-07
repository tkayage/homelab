---
phase: 01-infrastructure-design-and-prerequisites
plan: 05
subsystem: infrastructure
tags: [proxmox, docker-compose, postgres, capacity, topology]
requires:
  - phase: 01-infrastructure-design-and-prerequisites
    provides: Operator-approved environment evidence and three-guest topology from plan 01-04
provides:
  - Canonical three-guest infrastructure inventory
  - Compose service ownership and readiness contract
  - Verified capacity checks and operator-approved startup metadata
affects: [01-06, phase-02, phase-04, phase-05, provisioning]
tech-stack:
  added: []
  patterns: [three-guest-topology, compose-internal-readiness, observe-only-existing-services]
key-files:
  created: []
  modified: [infrastructure/inventory.json, docs/prerequisites.md, docs/architecture-boundaries.md]
key-decisions:
  - "Provision only postgres-01, services-01, and k3s-01 as new Proxmox guests."
  - "Run Valkey, NATS/JetStream, and Debezium inside services-01 under Docker Compose; Docker-in-LXC remains prohibited."
  - "Record approved startup metadata for existing Zitadel and NPM for later owner-controlled mutation without changing them in Phase 1."
patterns-established:
  - "Proxmox orders guests; Docker Compose orders and health-checks services inside services-01."
  - "Operator-confirmed local DNS identities are not represented as public Cloudflare evidence."
requirements-completed: [INFRA-03]
duration: 7min
completed: 2026-07-07
status: complete
---

# Phase 1 Plan 5: Consolidated Infrastructure Contract Summary

**The executable inventory now defines one PostgreSQL LXC, one supporting-services Compose VM, and one disposable k3s VM with measured capacity approval**

## Performance

- **Completed:** 2026-07-07T14:48:52Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments

- Removed obsolete Valkey, NATS, and Debezium Proxmox guest records and modeled them as explicit services inside `services-01`.
- Applied approved VMIDs, addresses, DNS names, resources, dependencies, and startup metadata for the three planned guests.
- Recorded capacity rechecks: CPU ratio 2.1 against maximum 2.5, memory headroom approximately 23.9%, and `local-lvm` storage headroom approximately 69.9% against 20% minimums.
- Preserved Zitadel as complete, `manual-existing`, observe-only, and unresized while recording its operator-confirmed local DNS identity and later desired startup metadata.
- Documented existing NPM at `proxy.kayage.co` and Zitadel at `zitadel.kayage.co` as local-only identities, not public Cloudflare records.

## Task Commits

1. **Task 1: Migrate the canonical contract and documentation** - `3a2d86d`

## Files Created/Modified

- `infrastructure/inventory.json` - Resolved three-guest topology, Compose services, measured capacity, and approved metadata.
- `docs/prerequisites.md` - Current evidence, approvals, existing systems, and remaining VLAN gate.
- `docs/architecture-boundaries.md` - Guest/service ownership, durability, and startup/readiness boundaries.

## Decisions Made

- `k3s-01` depends only on `postgres-01`, `services-01`, and `zitadel-existing`; Compose service identities are not Proxmox dependencies.
- Compose owns internal health and dependency checks for Valkey, NATS/JetStream, and Debezium.
- Existing Zitadel and NPM startup changes are approved for a later mutation phase but were not applied in Phase 1.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- VLAN mode remains unverified and explicitly blocks provisioning until it is confirmed tagged or untagged.
- The current validator still targets the obsolete five-guest contract; Plan 01-06 is responsible for its remediation.

## User Setup Required

None for this documentation-only plan.

## Next Phase Readiness

- Plan 01-06 can update policy enforcement against the canonical three-guest topology.
- No infrastructure or existing service was provisioned, resized, restarted, or reconfigured.

## Self-Check: PASSED

- The inventory contains exactly `postgres-01`, `services-01`, and `k3s-01` as OpenTofu-owned guests.
- `services-01` contains exactly Valkey, NATS, and Debezium service records.
- Planned resources total 10 vCPU, 20480 MiB memory, and 192 GiB disk.
- Both operator documents consistently describe the consolidated architecture.

---
*Phase: 01-infrastructure-design-and-prerequisites*
*Completed: 2026-07-07*
