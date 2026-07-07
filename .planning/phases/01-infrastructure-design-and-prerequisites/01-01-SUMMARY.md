---
phase: 01-infrastructure-design-and-prerequisites
plan: 01
subsystem: infrastructure
tags: [proxmox, inventory, capacity, networking, credentials]
requires: []
provides:
  - Canonical evidence-bearing Proxmox host and network inventory
  - Explicit capacity policy and proposed guest allocations
  - Secret-free access descriptors and infrastructure ownership boundaries
affects: [phase-02, phase-03, phase-04, phase-05, provisioning, gitops]
tech-stack:
  added: [RFC-8259-JSON]
  patterns: [evidence-bearing-site-facts, blocked-unknowns, least-privilege-descriptors]
key-files:
  created: [infrastructure/inventory.json]
  modified: []
key-decisions:
  - "Use minimum uncommitted physical-thread percentage as the proposed CPU capacity mode, pending operator approval."
  - "Represent all unknown site and existing Zitadel facts as null blocked evidence, never plausible placeholders."
patterns-established:
  - "Every environment-specific fact carries value, status, validation, and source metadata."
  - "Credential records describe identity, scope, storage, consumers, and lifecycle without fields for secret material."
requirements-completed: [INFRA-03]
coverage:
  - id: D1
    description: "Canonical infrastructure inventory defines explicit host, network, capacity, guest, ownership, and access contracts."
    requirement: "INFRA-03"
    verification:
      - kind: integration
        ref: "jq structural and policy queries against infrastructure/inventory.json"
        status: pass
    human_judgment: false
duration: 3min
completed: 2026-07-07
status: complete
---

# Phase 1 Plan 1: Canonical Infrastructure Inventory Summary

**Evidence-bearing JSON inventory for the single-MS-01 topology, including measurable capacity gates, six platform guests, and least-privilege access descriptors**

## Performance

- **Duration:** 3 min
- **Started:** 2026-07-07T12:31:00Z
- **Completed:** 2026-07-07T12:33:54Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Defined host, network, existing-allocation, and measurement facts so unavailable site data is explicitly blocked.
- Inventoried the disposable k3s VM, four native-service LXCs, and observe-only existing Zitadel LXC with proposed resources and startup dependencies.
- Established OpenTofu, configuration automation, Argo CD, and manual-existing ownership boundaries plus six secret-free credential descriptors.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define host, network, and capacity contracts** - `99bfa56` (feat)
2. **Task 2: Inventory guests, ownership, dependencies, and credential descriptors** - `aafe289` (feat)

## Files Created/Modified

- `infrastructure/inventory.json` - Canonical machine-readable infrastructure and prerequisite contract.

## Decisions Made

- Selected a proposed 20% minimum uncommitted physical-thread policy because it makes CPU reserve measurable; it remains pending explicit operator approval.
- Used null blocked evidence objects for unknown site identities and observed Zitadel capacity so later automation cannot mistake examples for production facts.
- Kept durable service configuration separate from guest lifecycle and restricted Argo CD ownership to Kubernetes resources.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None in this plan. Later Phase 1 plans collect and verify the blocked site facts and operator approval without provisioning infrastructure.

## Next Phase Readiness

- Phase 2 and Phase 5 can consume stable guest IDs, proposed allocations, dependencies, and ownership boundaries.
- Site-specific host, network, Zitadel, and capacity evidence remains intentionally blocked pending the prerequisite evidence plans.

## Self-Check: PASSED

- `infrastructure/inventory.json` exists and passes RFC 8259 parsing and all plan-specific jq assertions.
- Task commits `99bfa56` and `aafe289` exist in repository history.
- No secret-shaped fields or credential material were introduced.

---
*Phase: 01-infrastructure-design-and-prerequisites*
*Completed: 2026-07-07*
