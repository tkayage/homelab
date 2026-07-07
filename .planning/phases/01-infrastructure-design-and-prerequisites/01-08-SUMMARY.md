---
phase: 01-infrastructure-design-and-prerequisites
plan: 08
subsystem: infrastructure-validation
tags: [proxmox, storage, capacity, jq, policy-validation]
requires:
  - phase: 01-infrastructure-design-and-prerequisites
    provides: Canonical storage commitments and approved 20 percent storage reserve
provides:
  - Measured usable local-lvm capacity from the read-only Proxmox API
  - Derived storage-headroom enforcement with canonical commitment cross-checks
  - Negative tests for missing capacity, inconsistent claims, and reserve breaches
affects: [phase-02, provisioning, verification]
tech-stack:
  added: []
  patterns: [measured-denominator-capacity-policy, mutation-based-negative-tests]
key-files:
  created: [.planning/phases/01-infrastructure-design-and-prerequisites/01-08-SUMMARY.md]
  modified: [infrastructure/inventory.json, scripts/validate-inventory.sh, tests/test-inventory.sh, docs/prerequisites.md]
key-decisions:
  - "Storage headroom is computed from measured usable capacity, existing commitments, and planned allocations; the recorded percentage is only a consistency-checked projection."
requirements-completed: [INFRA-03]
coverage:
  - id: D1
    description: Measured usable capacity and reproducible storage headroom
    requirement: INFRA-03
    verification:
      - kind: command
        ref: "jq reproducibility assertion against infrastructure/inventory.json"
        status: pass
      - kind: api
        ref: "GET /api2/json/nodes/proxmox/storage/local-lvm/status at 2026-07-07T15:40:58Z"
        status: pass
    human_judgment: false
  - id: D2
    description: Derived threshold, claim consistency, and commitment cross-check enforcement
    requirement: INFRA-03
    verification:
      - kind: integration
        ref: "bash tests/test-inventory.sh"
        status: pass
      - kind: command
        ref: "bash scripts/validate-inventory.sh infrastructure/inventory.json"
        status: pass
    human_judgment: false
duration: 6min
completed: 2026-07-07
status: complete
---

# Phase 1 Plan 8: Derived Storage Headroom Summary

**Measured `local-lvm` capacity now drives storage-headroom policy, consistency checks, and targeted rejection tests.**

## Performance

- **Duration:** 6 min
- **Completed:** 2026-07-07T15:42:26Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Queried the read-only Proxmox storage-status API and recorded 1,836,111,101,952 bytes (1710.01 GiB) usable total capacity at `2026-07-07T15:40:58Z`.
- Reproduced the recorded 69.9% headroom from 1710.01 GiB total, 323.15 GiB existing commitments, and 192 GiB planned allocations.
- Replaced the trusted-percentage gate with derived threshold arithmetic, claim-consistency enforcement, and canonical commitment cross-checks.
- Added rejection coverage for inconsistent claims, derived reserve breaches, and missing measured capacity.

## Task Commits

1. **Task 1/2: Observe and record measured pool capacity** - `e9b2035`
2. **Task 3: Enforce derived storage arithmetic and add rejection coverage** - `7ae93f9`
3. **Acceptance reconciliation: Update operator-readable evidence** - `99cfe9c`

## Files Created/Modified

- `infrastructure/inventory.json` - Measured pool capacity and reproducible headroom evidence.
- `scripts/validate-inventory.sh` - Derived storage arithmetic and total cross-checks.
- `tests/test-inventory.sh` - Three targeted storage-capacity rejection cases.
- `docs/prerequisites.md` - Measured denominator and current completion state.

## Decisions Made

- `total_gib` represents the Proxmox storage-status API's usable total capacity converted from bytes using 2^30 and rounded to two decimals.
- A recorded headroom projection may differ from the derived value by at most 0.1 percentage points.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Reconciled human-readable capacity evidence**
- **Found during:** Plan-level acceptance review
- **Issue:** The prerequisite guide omitted the new measured denominator and still described Plan 01-08 as pending.
- **Fix:** Added the 1710.01 GiB measured capacity and updated the completion gate to require only re-verification.
- **Files modified:** `docs/prerequisites.md`
- **Verification:** Targeted `rg` consistency checks plus the complete inventory suite.
- **Committed in:** `99cfe9c`

**Total deviations:** 1 auto-fixed (1 missing critical consistency update).
**Impact:** Documentation now matches the canonical measured contract; no scope or infrastructure mutation was added.

## Authentication Gates

- Used `/home/tonny/.config/homelab/proxmox.env` for the read-only API request. No token, authorization header, cookie, password, or raw response body was recorded.

## Issues Encountered

None.

## User Setup Required

None - no external system was modified.

## Next Phase Readiness

- All nine Phase 1 plans are complete.
- The phase is ready for goal re-verification.

## Self-Check: PASSED

- `bash tests/test-inventory.sh` passes.
- `bash scripts/validate-inventory.sh infrastructure/inventory.json` passes.
- All three storage mutations are rejected with capacity diagnostics.
- Production commits and all modified artifacts exist.

---
*Phase: 01-infrastructure-design-and-prerequisites*
*Completed: 2026-07-07*
