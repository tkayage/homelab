---
phase: 05-shared-stateful-services
verified: 2026-07-08T20:44:00Z
status: gaps_found
score: 6/7
behavior_unverified: 0
overrides_applied: 0
gaps:
  - id: SERV-07-CANONICAL-CONTAINMENT
    requirement: SERV-07
    severity: blocker
    description: "Backup and restore use lexical pathname checks; POSTGRES_BACKUP_SUBDIR and symlinked parent components can resolve outside the mounted NAS export."
  - id: SERV-07-TOCTOU
    requirement: SERV-07
    severity: blocker
    description: "restore-test validates and later reopens the NAS pathname, so replacement between gzip validation and restore can feed different bytes to PostgreSQL."
  - id: SERV-07-REMOTE-INJECTION
    requirement: SERV-07
    severity: blocker
    description: "Environment-controlled scratch container name and image are interpolated into remote shell commands without validation or argument-safe quoting."
  - id: SERV-07-RESTORE-ERRORS
    requirement: SERV-07
    severity: blocker
    description: "The restore uses ON_ERROR_STOP=0, discards stderr, and asserts only the Debezium role, so partial SQL restore failures can be reported as success."
---

# Phase 05 Verification

## Verdict

Phase 5 is **not yet verified complete**. SERV-01 through SERV-06 retain credible
live evidence, but the repository's canonical SERV-07 restore procedure has three
critical correctness/security defects and one false-success path. The observed NAS
backup and scratch restore prove that one run succeeded; they do not prove that the
procedure reliably restores the exact validated NAS artifact or fails safely.

## Requirement Results

| Requirement | Status | Evidence |
|---|---|---|
| SERV-01 | VERIFIED | Live PostgreSQL 17 runs in dedicated unprivileged LXC `postgres-01`; the platform script and OpenTofu module remain present. |
| SERV-02 | VERIFIED | Live bounded Valkey on `services-01`; Compose configuration and static validation remain green. |
| SERV-03 | VERIFIED | Live NATS JetStream with bounded file/memory storage; configuration remains present and renders. |
| SERV-04 | VERIFIED | Live Debezium CDC, bounded PostgreSQL slot WAL, and observed JetStream heartbeat evidence remain recorded. |
| SERV-05 | VERIFIED | Live in-cluster checks reached all shared services through `*.shared-services.svc.cluster.local`; manifests still render. |
| SERV-06 | VERIFIED | Live Zitadel OIDC discovery through its valid-TLS hostname remains recorded and its service wiring still renders. |
| SERV-07 | FAILED (BLOCKER) | A NAS artifact restored once, but `scripts/postgres-platform.sh` does not securely bind validation to restored bytes and can report partial restores as successful. |

## SERV-07 Evidence Retained

The 05-06 execution produced useful live evidence:

- workstation `10.10.30.70` mounted
  `10.10.40.2:/volume1/homelab-backups` read/write;
- `/mnt/pg-backup/postgres/pg_dumpall_20260708_202625.sql.gz` was non-empty and
  gzip-valid;
- that pathname was supplied to a disposable `postgres:17` restore on
  `services-01`, the Debezium LOGIN/REPLICATION role was observed, and the scratch
  container was removed.

This evidence establishes off-host storage and a successful sample restore. It does
not close the repository-procedure defects below.

## Blocking Gaps

### 1. Canonical NAS containment is not enforced

`scripts/postgres-platform.sh` constructs `dest` from configurable
`POSTGRES_BACKUP_SUBDIR` and validates `backup_path` with lexical string comparisons.
It rejects only a symlink at the final pathname. `..` components or a symlinked
parent directory can make a compliant-looking path resolve outside the trusted NAS
mount for both backup creation and restore.

**Required fix:** restrict the subdirectory to a safe relative component and enforce
canonical, beneath-mount containment for both the destination and existing artifact,
including parent symlink handling.

### 2. Validation and restore can consume different bytes

The script separately opens the path for `test`, `gzip -t`, and `cat`. A file or
symlink replacement between these operations can cause PostgreSQL to consume bytes
other than those validated while the report retains the same pathname.

**Required fix:** open/copy the artifact once without following symlinks into a
private immutable local snapshot, hash it, validate that snapshot, and restore those
same bytes. Report the canonical NAS path and digest.

### 3. Remote shell command injection is possible

`POSTGRES_SCRATCH_NAME` and `POSTGRES_SCRATCH_IMAGE` flow unquoted into multiple
remote shell command strings, including the EXIT trap. Shell metacharacters can
execute unintended commands on `services-01` or target the wrong container.

**Required fix:** validate Docker name/reference syntax and pass values as positional
arguments to a fixed remote script that quotes every expansion.

### 4. SQL restore errors are ignored

The restore invokes `psql -v ON_ERROR_STOP=0`, suppresses stdout/stderr, and declares
success when only the Debezium role query returns one row. SQL failures and partial
database reconstruction can therefore pass.

**Required fix:** fail on SQL errors (or explicitly filter only known acceptable
diagnostics), preserve error output, and assert expected restored database/global
state before reporting success.

## Automated Regression Checks

- `bash -n scripts/postgres-platform.sh scripts/services-platform.sh tests/test-shared-services.sh` — PASS
- `bash tests/test-shared-services.sh static` — PASS
- `kubectl kustomize gitops/apps/shared-services >/dev/null` — PASS
- Debt-marker scan of Phase 5 runtime/config artifacts — no blocker markers found

Live backup/restore was not repeated during verification because it mutates external
infrastructure. The dated executor evidence above was assessed against the actual
implementation and the independent code-review findings.

## Next Action

Fix all four SERV-07 defects in `scripts/postgres-platform.sh`, add deterministic
tests for containment, immutable exact-byte handoff, hostile environment values, and
SQL failure propagation, then repeat the paired NAS backup/restore and re-run Phase 5
verification.

## Verification Complete

**Status:** `gaps_found`

**Score:** 6/7 requirements verified
