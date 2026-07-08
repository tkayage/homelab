---
phase: 05
slug: shared-stateful-services
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-07
updated: 2026-07-08
---

# Phase 05 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash validation scripts, OpenTofu validation, Docker Compose validation, and kubectl Kustomize rendering |
| **Config file** | `tests/test-shared-services.sh`, `infrastructure/opentofu/postgres/`, `infrastructure/opentofu/services/` |
| **Quick run command** | `bash -n scripts/postgres-platform.sh scripts/services-platform.sh tests/test-shared-services.sh && bash tests/test-shared-services.sh static` |
| **Full suite command** | `bash tests/test-shared-services.sh static && bash scripts/postgres-platform.sh validate && bash scripts/services-platform.sh validate` |
| **Estimated runtime** | Static checks under 60 seconds; live service checks depend on LAN responses |

## Sampling Rate

- **After every task commit:** Run the task's automated command from the map below.
- **After every plan wave:** Run the quick command; after Waves 4 and 5 also run the relevant live commands.
- **Before `/gsd-verify-work`:** Run the full suite plus `bash tests/test-shared-services.sh live` and the exact-path backup/restore pair from 05-06.
- **Max feedback latency:** 60 seconds for static checks; live infrastructure commands fail on their own bounded connection/readiness checks.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | SERV-01 | T-05-01 | LXC module validates as unprivileged infrastructure | static | `tofu -chdir=infrastructure/opentofu/postgres fmt -check && tofu -chdir=infrastructure/opentofu/postgres validate` | ✅ | ✅ green |
| 05-01-02 | 01 | 1 | SERV-01, SERV-07 | T-05-02, T-05-03 | Platform script is syntactically valid and exposes the required lifecycle | static | `bash -n scripts/postgres-platform.sh && test -x scripts/postgres-platform.sh` | ✅ | ✅ green |
| 05-02-01 | 02 | 1 | SERV-02, SERV-03, SERV-04 | T-05-04 | Services VM module validates with bounded sizing | static | `tofu -chdir=infrastructure/opentofu/services fmt -check && tofu -chdir=infrastructure/opentofu/services validate` | ✅ | ✅ green |
| 05-02-02 | 02 | 1 | SERV-02, SERV-03, SERV-04 | T-05-05 | Services lifecycle script is executable and syntactically valid | static | `bash -n scripts/services-platform.sh && test -x scripts/services-platform.sh` | ✅ | ✅ green |
| 05-03-01 | 03 | 2 | SERV-02, SERV-03, SERV-04 | T-05-06, T-05-07, T-05-08 | Compose and service configuration render without embedding runtime secrets | static | `docker compose -f infrastructure/services/docker-compose.yaml config --quiet && rg -q 'max_file_store: 4Gb' infrastructure/services/nats.conf` | ✅ | ✅ green |
| 05-03-02 | 03 | 2 | SERV-02, SERV-03, SERV-04 | T-05-08 | Deploy path requires the remote `.env` and script remains valid | static | `bash -n scripts/services-platform.sh && rg -q '/opt/homelab/services/.env' scripts/services-platform.sh` | ✅ | ✅ green |
| 05-04-01 | 04 | 3 | SERV-05, SERV-06 | T-05-09, T-05-10 | Selectorless Services and EndpointSlices render together | static | `kubectl kustomize gitops/apps/shared-services >/dev/null` | ✅ | ✅ green |
| 05-04-02 | 04 | 3 | SERV-05, SERV-06 | T-05-09, T-05-10 | Shared-service test harness parses and passes offline checks | static | `bash -n tests/test-shared-services.sh && bash tests/test-shared-services.sh static` | ✅ | ✅ green |
| 05-05-01 | 05 | 4 | SERV-01, SERV-07 | T-05-01, T-05-02 | Live PostgreSQL configuration and restore checks pass | live | `bash scripts/postgres-platform.sh validate && bash scripts/postgres-platform.sh backup && bash scripts/postgres-platform.sh restore-test` | ✅ | ✅ green (executed; NAS half superseded by 05-06 exact-path check) |
| 05-05-02 | 05 | 4 | SERV-02, SERV-03, SERV-04 | T-05-04 through T-05-08 | All three Compose services are live and healthy | live | `bash scripts/services-platform.sh validate` | ✅ | ✅ green |
| 05-05-03 | 05 | 4 | SERV-05, SERV-06 | T-05-09, T-05-10 | In-cluster DNS and service connectivity pass | live | `bash tests/test-shared-services.sh static && bash tests/test-shared-services.sh live` | ✅ | ✅ green |
| 05-06-01 | 06 | 5 | SERV-07 | T-05-06-01 | Exact NFS export accepts a scoped write/read/delete probe | live | `tmp=$(mktemp -d) && sudo mount -t nfs -o hard,nfsvers=4,noatime 10.10.40.2:/volume1/homelab-backups "$tmp" && probe="$tmp/.serv-07-write-${USER}-$$" && printf probe | sudo tee "$probe" >/dev/null && sudo test -s "$probe" && sudo rm -f "$probe"; rc=$?; mountpoint -q "$tmp" && sudo umount "$tmp"; rmdir "$tmp"; exit $rc` | ✅ | ⬜ pending operator grant |
| 05-06-02 | 06 | 5 | SERV-07 | T-05-06-02 through T-05-06-05 | Restore consumes the exact path emitted by its paired backup | live | `backup_output=$(bash scripts/postgres-platform.sh backup) && backup_path=$(printf '%s\n' "$backup_output" | sed -n 's/^BACKUP_PATH=//p') && test "$(printf '%s\n' "$backup_path" | wc -l)" -eq 1 && bash scripts/postgres-platform.sh restore-test "$backup_path"` | ✅ | ⬜ pending operator grant |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. `tests/test-shared-services.sh` and both platform scripts already exist; the legacy plan tasks now carry explicit automated verification commands. No test scaffold is missing.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Authorize workstation `10.10.30.70` for read/write NFS access | SERV-07 | NAS administration credentials and API access are outside the repository | Add the client-scoped rule for `/volume1/homelab-backups`; acceptance remains automated by task 05-06-01's mount/write/read/delete probe. |

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands and no Wave 0 dependencies are missing.
- [x] Sampling continuity: every task has an automated command.
- [x] No unresolved `MISSING` references remain.
- [x] No watch-mode flags are used.
- [x] Static feedback latency is under 60 seconds.
- [x] `nyquist_compliant: true` is set in frontmatter.

**Approval:** approved 2026-07-08
