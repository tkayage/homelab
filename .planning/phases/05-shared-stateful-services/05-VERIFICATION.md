---
phase: 05-shared-stateful-services
verified: 2026-07-08T20:25:17Z
status: passed
score: 7/7 requirements live-verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
---

# Phase 05 Verification

All seven Shared Services requirements are live-verified. SERV-01 through SERV-06
retain the deployment evidence recorded by plan 05-05. Plan 05-06 closes SERV-07
with a real NAS-resident backup and isolated restore of that exact artifact.

## SERV-07 Live Evidence — 2026-07-08

- NFS authorization probe: mounted
  `10.10.40.2:/volume1/homelab-backups` from workstation `10.10.30.70` with
  `hard,nfsvers=4,noatime`, wrote and read a non-empty probe, removed it, and
  unmounted successfully.
- Backup command: `bash scripts/postgres-platform.sh backup`
- Exact NAS path emitted by that run:
  `/mnt/pg-backup/postgres/pg_dumpall_20260708_202625.sql.gz`
- Backup validation: the file was non-empty and `gzip -t` passed while the NAS
  export was mounted.
- Restore command:
  `bash scripts/postgres-platform.sh restore-test "/mnt/pg-backup/postgres/pg_dumpall_20260708_202625.sql.gz"`
- Restore result: the same pathname was streamed into a disposable
  `postgres:17` container on `services-01`; the Debezium role was reconstructed
  with LOGIN and REPLICATION, one non-template database was present, and the
  scratch container was removed.

## Requirements Traceability

- SERV-01 — passed: PostgreSQL 17 runs in dedicated LXC `postgres-01`.
- SERV-02 — passed: bounded Valkey runs on `services-01`.
- SERV-03 — passed: bounded NATS JetStream runs on `services-01`.
- SERV-04 — passed: Debezium CDC and bounded replication-slot WAL are live.
- SERV-05 — passed: k3s workloads reach stable shared-service names.
- SERV-06 — passed: existing Zitadel integration is live.
- SERV-07 — passed: a real off-host NAS backup is non-empty, gzip-valid, and
  restores successfully into an isolated PostgreSQL 17 scratch instance.

## Conclusion

Phase 5 is complete: 7/7 requirements live-verified with no deferred behaviors.
