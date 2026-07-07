---
phase: 01-infrastructure-design-and-prerequisites
plan: 06
subsystem: testing
tags: [proxmox, inventory, docker-compose, policy-validation]
requires:
  - phase: 01-infrastructure-design-and-prerequisites
    provides: Canonical three-guest inventory and Compose service contract from plan 01-05
provides:
  - Exact policy enforcement for the three-new-guest topology
  - Rejection coverage for obsolete guests, Docker-in-LXC, dependency drift, and capacity breaches
  - Verified untagged vmbr0 network evidence
affects: [01-07, phase-02, provisioning]
tech-stack:
  added: []
  patterns: [canonical-inventory-derived-tests, focused-mutation-fixtures]
key-files:
  created: []
  modified: [scripts/validate-inventory.sh, tests/test-inventory.sh, tests/fixtures, infrastructure/inventory.json]
key-decisions:
  - "Only postgres-01 LXC, services-01 VM, and k3s-01 VM may be OpenTofu-owned guests."
  - "Compose readiness and dependencies are validated inside services-01 without assigning Proxmox orders to embedded services."
patterns-established:
  - "Negative fixtures are focused jq mutations applied to the canonical valid inventory."
requirements-completed: [INFRA-03]
coverage:
  - id: D1
    description: Exact consolidated topology and capacity policy validator
    requirement: INFRA-03
    verification:
      - kind: integration
        ref: "bash tests/test-inventory.sh"
        status: pass
    human_judgment: false
  - id: D2
    description: Canonical inventory passes the complete validator with untagged VLAN evidence
    requirement: INFRA-03
    verification:
      - kind: integration
        ref: "bash scripts/validate-inventory.sh infrastructure/inventory.json"
        status: pass
    human_judgment: false
duration: 8min
completed: 2026-07-07
status: complete
---

# Phase 1 Plan 6: Consolidated Topology Validation Summary

**The inventory gate now accepts only the approved PostgreSQL LXC, services Compose VM, and disposable k3s VM topology while enforcing capacity and ownership boundaries**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-07T14:46:00Z
- **Completed:** 2026-07-07T14:54:34Z
- **Tasks:** 1
- **Files modified:** 7

## Accomplishments

- Replaced obsolete per-service LXC checks with exact identities, allocations, startup values, aggregate capacity, and dependency checks for three new guests.
- Added Compose-level service set, JetStream mode, readiness, dependency, and VM-only Docker enforcement.
- Converted invalid fixtures to focused mutations and added rejection coverage for topology, allocation, dependency, readiness, evidence, identity, secrets, and capacity failures.
- Resolved the final VLAN evidence as untagged based on active `vmbr0` having no tag and no VLAN-aware setting.

## Task Commits

1. **Task 1: Update topology validation and fixtures** - `741ecd9`

## Files Created/Modified

- `scripts/validate-inventory.sh` - Enforces the exact consolidated architecture and approved capacity policies.
- `tests/test-inventory.sh` - Exercises canonical acceptance and focused policy rejection cases.
- `tests/fixtures/*.json` - Single-purpose invalid inventory mutations.
- `infrastructure/inventory.json` - Records verified untagged VLAN mode from Proxmox evidence.

## Decisions Made

- Existing `zitadel-existing` remains observe-only and is excluded from planned resource totals.
- Credential metadata labels remain allowed, while actual token/password/key-shaped fields remain prohibited.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Resolved the required VLAN evidence**
- **Found during:** Task 1 canonical acceptance test
- **Issue:** The canonical inventory remained blocked on VLAN mode, preventing the required final validator pass.
- **Fix:** Recorded `vmbr0` as untagged using read-only Proxmox evidence showing no tag and no VLAN-aware setting.
- **Files modified:** `infrastructure/inventory.json`
- **Verification:** `bash scripts/validate-inventory.sh infrastructure/inventory.json`
- **Committed in:** `741ecd9`

**Total deviations:** 1 auto-fixed (1 blocking issue)
**Impact on plan:** The change resolves evidence explicitly required by the final policy gate; no infrastructure was mutated.

## Issues Encountered

- The previous validator assumed every evidence leaf included a validation narrative and expected a retired capacity schema. Validation was aligned with the canonical inventory while retaining verified status, source attribution, approvals, arithmetic, and reserve gates.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 01-07 can execute the complete Phase 1 gate against a resolved canonical inventory.
- No Proxmox guest or existing service was provisioned or reconfigured.

---
*Phase: 01-infrastructure-design-and-prerequisites*
*Completed: 2026-07-07*
