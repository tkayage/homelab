---
phase: 05-shared-stateful-services
reviewed: 2026-07-08T20:35:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - scripts/postgres-platform.sh
findings:
  critical: 3
  warning: 1
  info: 0
  total: 4
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-07-08T20:35:00Z
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found

## Summary

The explicit `BACKUP_PATH` argument removes the previous latest-file race, but the implementation does not yet prove that the bytes restored are the bytes validated or that the lexical path is contained by the mounted NAS directory. Configurable values are also interpolated into remote shell commands without quoting. These are release-blocking because they can redirect backup/restore outside the intended artifact boundary or execute unintended commands on `services-01`.

## Critical Issues

### CR-01: Lexical checks do not enforce canonical NAS containment

**File:** `scripts/postgres-platform.sh:179-187`
**Issue:** The checks compare strings and reject only a symlink at the final pathname. They do not canonicalize `dest` or `backup_path`, and they do not reject symlinks in parent components. For example, an NFS-side `postgres` directory symlink can make `/mnt/pg-backup/postgres/pg_dumpall_*.sql.gz` resolve outside the mounted export while all current checks pass. `POSTGRES_BACKUP_SUBDIR` can likewise contain `..`. Backup creation at lines 154-158 follows the same unsafe directory path, so a run can write outside the NAS and still emit a compliant-looking `BACKUP_PATH`.
**Fix:** Require `backup_subdir` to be one safe relative component, canonicalize the mount and destination with `realpath`, require the destination's canonical path to be below the canonical mount, and canonicalize the existing artifact with `realpath -e` before testing containment. Reject any symlink component (for example with `namei`) or open relative to a trusted directory using `openat2`/`RESOLVE_BENEATH` via a small helper. Apply the same validated destination to both backup and restore.

### CR-02: Validation and restore can consume different bytes

**File:** `scripts/postgres-platform.sh:184-197`
**Issue:** `test`, `gzip -t`, and the later `cat` each reopen the pathname. The NAS file can be replaced between validation and streaming, including by a symlink introduced after the `! -L` check. Consequently the command can restore content different from the gzip-valid artifact it validated while reporting the same pathname, violating the exact-artifact handoff and the plan's tampering control.
**Fix:** Open the artifact once without following symlinks and retain that descriptor through validation and restore. Copy the opened bytes into a private local temporary file while hashing them, validate that file with `gzip -t`, restore that same immutable file, and report both the canonical NAS pathname and digest. Alternatively use a descriptor-based helper with `O_NOFOLLOW` and verify inode/device metadata remains unchanged; do not reopen the pathname after validation.

### CR-03: Configurable values are injected into remote shell command strings

**File:** `scripts/postgres-platform.sh:178-200`
**Issue:** `scratch_name` and `scratch_image` are sourced from environment variables and interpolated unquoted into commands interpreted by the remote shell. Values such as `POSTGRES_SCRATCH_NAME='x; command #'` execute arbitrary commands on `services-01`; the EXIT trap repeats the injection path. Whitespace and shell metacharacters also cause ordinary malformed values to target or remove unintended containers.
**Fix:** Validate both values against strict Docker reference/name allowlists before use and shell-quote every remote argument. Prefer passing positional arguments to a fixed remote script, e.g. `ssh_svc bash -s -- "$scratch_name" "$scratch_image"`, with a single-quoted heredoc/script body that uses `"$1"` and `"$2"` locally on the remote host.

## Warnings

### WR-01: Restore errors are deliberately ignored

**File:** `scripts/postgres-platform.sh:197-205`
**Issue:** The restore runs `psql -v ON_ERROR_STOP=0`, suppresses all output, and declares success from only one role count. SQL failures or a partial restore can therefore be reported as a successful restore when the Debezium role happens to exist. The database count is displayed but never asserted, so it does not establish successful reconstruction.
**Fix:** Use `ON_ERROR_STOP=1`, retain stderr on failure, and assert the expected restored database/global state before printing success. If known `pg_dumpall --clean` diagnostics must be tolerated, filter only those explicitly rather than disabling error-stop globally.

---

_Reviewed: 2026-07-08T20:35:00Z_
_Reviewer: the agent (gsd-code-reviewer; generic-agent workaround)_
_Depth: standard_
