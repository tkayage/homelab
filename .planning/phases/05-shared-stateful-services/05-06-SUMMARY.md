---
phase: 05-shared-stateful-services
plan: 06
subsystem: infra
tags: [postgresql, nfs, nas, backup, restore]
requires:
  - phase: 05-shared-stateful-services
    provides: live PostgreSQL 17 LXC and disposable restore host
provides:
  - deterministic backup-path handoff from NAS backup to isolated restore
  - live off-host backup and restore evidence for SERV-07
  - completed Phase 5 verification and milestone status
affects: [phase-8-operations, backup-recovery]
tech-stack:
  added: []
  patterns: [exact-artifact restore verification, workstation-mediated NFS backup]
key-files:
  created: [.planning/phases/05-shared-stateful-services/05-06-SUMMARY.md]
  modified: [scripts/postgres-platform.sh, .planning/phases/05-shared-stateful-services/05-VERIFICATION.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md, .planning/STATE.md]
key-decisions:
  - "Restore accepts only the exact canonical NAS path emitted by backup."
  - "SERV-07 closes only after a real NAS write and disposable PostgreSQL 17 restore both pass."
patterns-established:
  - "Backup producers emit one stable BACKUP_PATH line consumed explicitly by restore verification."
requirements-completed: [SERV-07]
coverage:
  - id: D1
    description: "A fresh PostgreSQL dump is stored on the off-host NAS and the exact artifact restores in isolation."
    requirement: SERV-07
    verification:
      - kind: e2e
        ref: "bash scripts/postgres-platform.sh backup; bash scripts/postgres-platform.sh restore-test $backup_path"
        status: pass
      - kind: manual_procedural
        ref: "NFSv4 mount/write/read/delete probe from 10.10.30.70"
        status: pass
    human_judgment: false
duration: 6min
completed: 2026-07-08
status: complete
---

# Phase 5 Plan 06: NAS Backup Gap Closure Summary

**A real pg_dumpall reached the NAS and that exact gzip artifact restored into a disposable PostgreSQL 17 container**

## Performance

- **Duration:** 6 min
- **Started:** 2026-07-08T20:21:00Z
- **Completed:** 2026-07-08T20:26:52Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Proved workstation `10.10.30.70` has read/write NFSv4 access to `10.10.40.2:/volume1/homelab-backups` with a mount/write/read/delete probe.
- Created and validated `/mnt/pg-backup/postgres/pg_dumpall_20260708_202625.sql.gz` on the NAS.
- Restored that exact pathname into disposable `postgres:17` on `services-01`, verified the Debezium LOGIN/REPLICATION role, and removed the scratch container.
- Marked SERV-07 and Phase 5 complete from dated canonical live evidence.

## Task Commits

1. **Task 1: Authorize the workstation on the NAS NFS export** — external operator action; automated probe passed
2. **Task 2: Write a real backup to NAS, restore it, and close canonical evidence** — `03c529d`

## Files Created/Modified

- `scripts/postgres-platform.sh` — emits and validates an exact NAS backup path; restores only an explicitly supplied canonical artifact.
- `.planning/phases/05-shared-stateful-services/05-VERIFICATION.md` — records the live NAS path and successful isolated restore.
- `.planning/REQUIREMENTS.md` — marks SERV-07 complete.
- `.planning/ROADMAP.md` — records Phase 5 as 6/6 plans complete.
- `.planning/STATE.md` — removes deferred Phase 5 verification while preserving the completed Phase 6 position.
- `.planning/phases/05-shared-stateful-services/05-06-SUMMARY.md` — records execution results.

## Decisions Made

- Kept the Phase 5 workstation-mediated NFS design and client-scoped NAS authorization.
- Bound restore verification to the exact `BACKUP_PATH` emitted by the immediately preceding backup, eliminating latest-file races.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Reject symbolic-link backup paths**

- **Found during:** Task 2
- **Issue:** A lexical path inside the canonical directory could be a symbolic link to content outside it.
- **Fix:** Reject symbolic links before validating and streaming the artifact.
- **Files modified:** `scripts/postgres-platform.sh`
- **Verification:** The accepted real artifact was a regular, non-empty, gzip-valid file and restored successfully.
- **Committed in:** `03c529d`

**Total deviations:** 1 auto-fixed (1 missing critical functionality). **Impact:** Strengthened the planned canonical-path boundary without changing architecture or scope.

## Issues Encountered

- The initial NFS permission checkpoint had previously failed with `access denied by server`; after the operator grant, the exact probe passed.

## User Setup Required

Completed: the NAS export now grants read/write access to workstation `10.10.30.70`.

## Next Phase Readiness

- Phase 5 is fully live-verified at 7/7 requirements with no deferred verification.
- Phase 6 remains complete; Phase 7 can be planned next.

## Self-Check: PASSED

- Summary key files exist.
- Task commit `03c529d` exists.
- NFS probe, paired backup/restore, exact-path identity, scratch cleanup, and canonical status checks all passed.

---
*Phase: 05-shared-stateful-services*
*Completed: 2026-07-08*
