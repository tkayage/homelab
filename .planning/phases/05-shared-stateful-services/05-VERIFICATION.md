---
phase: 05-shared-stateful-services
verified: 2026-07-09T08:17:30Z
status: passed
score: 7/7
behavior_unverified: 0
overrides_applied: 0
gaps: []
---

# Phase 05 Verification

## Verdict

Phase 5 is verified complete. SERV-01 through SERV-06 retain their prior live
evidence, and SERV-07 is now backed by hardened repository code, deterministic
static regression checks, and a fresh paired NAS backup/restore proof.
This verification was refreshed after `05-07-SUMMARY.md` was created so the GSD
staleness gate sees the verification as current.

## Requirement Results

| Requirement | Status | Evidence |
|---|---|---|
| SERV-01 | VERIFIED | Live PostgreSQL 17 runs in dedicated unprivileged LXC `postgres-01`; the platform script and OpenTofu module remain present. |
| SERV-02 | VERIFIED | Live bounded Valkey on `services-01`; Compose configuration and static validation remain green. |
| SERV-03 | VERIFIED | Live NATS JetStream with bounded file/memory storage; configuration remains present and renders. |
| SERV-04 | VERIFIED | Live Debezium CDC, bounded PostgreSQL slot WAL, and observed JetStream heartbeat evidence remain recorded. |
| SERV-05 | VERIFIED | Live in-cluster checks reached all shared services through `*.shared-services.svc.cluster.local`; manifests still render. |
| SERV-06 | VERIFIED | Live Zitadel OIDC discovery through its valid-TLS hostname remains recorded and its service wiring still renders. |
| SERV-07 | VERIFIED | Fresh NAS artifact `/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz` restored into disposable `postgres:17` from a hashed local snapshot with SQL error-stop semantics. |

## SERV-07 Hardened Evidence

- `POSTGRES_BACKUP_SUBDIR` is accepted only as one safe relative component.
- Backup destination and restore artifact paths are resolved with `realpath -e`,
  checked beneath the canonical NAS mount/destination, and rejected if any path
  component is a symlink.
- `restore-test` copies the selected NAS artifact once into a private `mktemp -d`
  snapshot, computes SHA-256, gzip-validates the snapshot, and restores those
  same bytes.
- `POSTGRES_SCRATCH_NAME` and `POSTGRES_SCRATCH_IMAGE` are strict-validated
  before remote Docker operations.
- Remote Docker startup uses fixed shell code with scratch values passed as
  positional arguments and quoted at each expansion.
- SQL restore runs with `ON_ERROR_STOP=1`, preserves restore output on failure,
  and filters only the two exact `pg_dumpall --clean` self-role statements that
  cannot run against the current scratch `postgres` user.
- Success requires both the Debezium LOGIN/REPLICATION role and a non-zero
  non-template database count.

## Fresh Live Proof

- Backup command: `bash scripts/postgres-platform.sh backup`
- Backup result:
  `BACKUP_PATH=/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz`
- Restore command:
  `bash scripts/postgres-platform.sh restore-test "$backup_path"`
- Restore result:
  `Restore verification passed for /mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz (sha256=e6b85d04a11a7e3508770702604a996dd8eace9f9340abdf599d42f908a30e15, scratch postgres:17: debezium role reconstructed, 1 database(s) restored)`

## Automated Regression Checks

- `bash -n scripts/postgres-platform.sh tests/test-shared-services.sh` - PASS
- `bash tests/test-shared-services.sh static` - PASS
- `kubectl kustomize gitops/apps/shared-services >/dev/null` - PASS

## Verification Complete

**Status:** `passed`

**Score:** 7/7 requirements verified
