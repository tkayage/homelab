---
phase: 05-shared-stateful-services
plan: 07
subsystem: infra
tags: [postgresql, nfs, nas, backup, restore, security]
requires:
  - phase: 05-shared-stateful-services
    provides: live PostgreSQL 17 LXC, services-01 Docker host, and NAS NFS backup export
provides:
  - Hardened canonical PostgreSQL NAS backup and restore-test procedure
  - Deterministic static regression checks for SERV-07 hardening controls
  - Fresh live NAS backup/restore proof with snapshot digest
affects: [phase-8-operations, backup-recovery, shared-services]
tech-stack:
  added: []
  patterns: [canonical path containment, exact-byte restore snapshot, positional remote shell arguments, SQL error-stop restore]
key-files:
  created: [.planning/phases/05-shared-stateful-services/05-07-SUMMARY.md, .planning/phases/05-shared-stateful-services/05-UAT.md]
  modified: [scripts/postgres-platform.sh, tests/test-shared-services.sh, .planning/phases/05-shared-stateful-services/05-VERIFICATION.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md, .planning/STATE.md]
key-decisions:
  - "SERV-07 restore proof binds validation and restore to a single local snapshot copied from the selected NAS artifact."
  - "SQL restore runs with ON_ERROR_STOP=1 and filters only the two exact pg_dumpall self-role statements that cannot run against the current scratch postgres user."
patterns-established:
  - "Canonical containment: validate a safe relative subdirectory, resolve paths with realpath, and reject symlink components before accepting NAS artifacts."
  - "Remote shell safety: validate operator-controlled Docker values before passing them into fixed remote scripts."
requirements-completed: [SERV-07]
coverage:
  - id: D1
    description: "PostgreSQL NAS backup and restore-test procedure rejects path escape and symlink component escapes."
    requirement: SERV-07
    verification:
      - kind: integration
        ref: "bash tests/test-shared-services.sh static"
        status: pass
    human_judgment: false
  - id: D2
    description: "restore-test validates and restores one immutable local snapshot copied from the selected NAS artifact, with a reported SHA-256 digest."
    requirement: SERV-07
    verification:
      - kind: e2e
        ref: "bash scripts/postgres-platform.sh backup; bash scripts/postgres-platform.sh restore-test /mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz"
        status: pass
    human_judgment: false
  - id: D3
    description: "Remote scratch container values are strict-validated before remote Docker operations."
    requirement: SERV-07
    verification:
      - kind: integration
        ref: "bash tests/test-shared-services.sh static"
        status: pass
    human_judgment: false
  - id: D4
    description: "SQL restore failures are no longer suppressed, and success asserts restored Debezium role plus database state."
    requirement: SERV-07
    verification:
      - kind: e2e
        ref: "restore-test output sha256=e6b85d04a11a7e3508770702604a996dd8eace9f9340abdf599d42f908a30e15"
        status: pass
    human_judgment: false
duration: 23 min
completed: 2026-07-09
status: complete
---

# Phase 5 Plan 07: SERV-07 Hardening Summary

**PostgreSQL NAS restore verification now binds canonical artifact validation to a hashed snapshot and SQL error-stop restore**

## Performance

- **Duration:** 23 min
- **Started:** 2026-07-09T07:48:00Z
- **Completed:** 2026-07-09T08:10:37Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Added static regression checks that enforce the SERV-07 hardening contract for canonical containment, exact-byte snapshot restore, remote argument safety, and SQL failure propagation.
- Hardened `scripts/postgres-platform.sh` so backup/restore uses safe backup subdirectory validation, canonical NAS containment checks, symlink component rejection, strict scratch Docker value validation, and quoted remote execution.
- Changed restore-test to copy the selected NAS artifact once into a private local snapshot, compute SHA-256, gzip-validate that snapshot, and restore that same stream into the disposable PostgreSQL container.
- Reran a fresh live NAS backup/restore proof for `/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz`, digest `e6b85d04a11a7e3508770702604a996dd8eace9f9340abdf599d42f908a30e15`.
- Re-closed Phase 5/SERV-07 across verification, automated UAT, roadmap, requirements, and state artifacts.

## Task Commits

1. **Tasks 1-2: Add regression tests and harden backup/restore handling** - `ee419f8` (fix)
2. **Task 3: Rerun live NAS backup/restore and close SERV-07 status** - metadata commit (docs)

## Files Created/Modified

- `scripts/postgres-platform.sh` - Adds input validation, canonical containment, immutable snapshot restore, SQL error-stop behavior, and preserved restore failure output.
- `tests/test-shared-services.sh` - Adds deterministic static assertions for the SERV-07 hardening controls.
- `.planning/phases/05-shared-stateful-services/05-VERIFICATION.md` - Records passed 7/7 verification and fresh live evidence.
- `.planning/phases/05-shared-stateful-services/05-UAT.md` - Records automated UAT passes from coverage-backed deliverables.
- `.planning/REQUIREMENTS.md` - Updates SERV-07 evidence to the hardened 05-07 proof.
- `.planning/ROADMAP.md` - Marks Phase 5 and 05-07 complete.
- `.planning/STATE.md` - Clears deferred Phase 5 verification and restores ready-for-Phase-7 status.

## Decisions Made

- Kept workstation-mediated NAS backup architecture, but made restore verification bind to one hashed local snapshot copied from the explicit NAS artifact.
- Kept `pg_dumpall --clean --if-exists`, while filtering only the two exact self-role statements (`DROP ROLE IF EXISTS postgres;` and `CREATE ROLE postgres;`) that cannot execute against the current scratch `postgres` user under `ON_ERROR_STOP=1`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Avoid remote restore stdin collision**

- **Found during:** Task 3 live restore
- **Issue:** A first hardening attempt sent the remote restore script and SQL stream over the same SSH stdin, causing `psql` to consume part of the shell script.
- **Fix:** Switched the remote restore wrapper to a quoted `bash -c` command so stdin is reserved for the decompressed snapshot stream.
- **Files modified:** `scripts/postgres-platform.sh`
- **Verification:** Fresh live restore reached SQL execution and no longer consumed shell wrapper text.
- **Committed in:** `ee419f8`

**2. [Rule 2 - Missing Critical] Preserve SQL error-stop while tolerating pg_dumpall self-role statements**

- **Found during:** Task 3 live restore
- **Issue:** `ON_ERROR_STOP=1` correctly failed when `pg_dumpall --clean` tried to drop the current scratch `postgres` user.
- **Fix:** Filtered only exact `DROP ROLE IF EXISTS postgres;` and `CREATE ROLE postgres;` lines before restore, preserving fatal behavior for all other SQL errors.
- **Files modified:** `scripts/postgres-platform.sh`
- **Verification:** Fresh live restore completed with digest output and restored-state assertions.
- **Committed in:** `ee419f8`

**Total deviations:** 2 auto-fixed (2 missing critical execution details). **Impact:** Both fixes preserve the planned security model and were required for the hardened live proof to execute correctly.

## Issues Encountered

- The live backup/restore proof initially failed twice during hardening: once from SSH stdin collision and once from the expected `pg_dumpall --clean` self-role statement under SQL error-stop. Both were fixed before closure.

## User Setup Required

None - NAS NFS access for workstation `10.10.30.70` was already in place from 05-06.

## Next Phase Readiness

Phase 5 is fully verified at 7/7 requirements. Phase 6 remains complete. Phase 7 can proceed with opt-in public exposure work.

## Self-Check: PASSED

- `bash -n scripts/postgres-platform.sh tests/test-shared-services.sh` passed.
- `bash tests/test-shared-services.sh static` passed.
- Fresh backup emitted exactly one `BACKUP_PATH=/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz`.
- `restore-test "$backup_path"` reported the same path, SHA-256 digest, Debezium role reconstruction, and restored database count.
- `05-VERIFICATION.md`, `REQUIREMENTS.md`, `ROADMAP.md`, and `STATE.md` agree that SERV-07 and Phase 5 are complete.

---
*Phase: 05-shared-stateful-services*
*Completed: 2026-07-09*
