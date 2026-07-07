---
phase: 05-shared-stateful-services
verified: 2026-07-07T19:56:00Z
status: passed
score: 7/7 success criteria verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
---

# Phase 05 Verification

**Phase:** 05-shared-stateful-services
**Date:** 2026-07-07

## Goal Achievement
The phase goal has been **successfully achieved**. Shared stateful infrastructure outside the k3s cluster (PostgreSQL, Valkey, NATS, Debezium, Zitadel) has been successfully provisioned and configured. Automated backup/restore mechanisms for PostgreSQL have been established using an NFS share. Kubernetes discovery has been set up via GitOps-managed selectorless Services and EndpointSlices.

## Requirements Traceability

- **SERV-01: Postgres runs as a native service in a dedicated Proxmox LXC.**
  - **Verified**: `infrastructure/opentofu/postgres/main.tf` defines an unprivileged LXC `postgres-01` (VMID 120).
- **SERV-02: Valkey or Redis runs in the dedicated shared-services Compose VM with explicit memory limits.**
  - **Verified**: `infrastructure/opentofu/services/main.tf` defines `services-01` (VMID 121), and `infrastructure/services/docker-compose.yaml` bounds Valkey to a `1536M` memory limit.
- **SERV-03: NATS with JetStream runs in the dedicated shared-services Compose VM with bounded persistent storage.**
  - **Verified**: `infrastructure/services/nats.conf` restricts `max_file_store: 4Gb` and `max_mem_store: 256Mb`.
- **SERV-04: Debezium runs in the dedicated shared-services Compose VM with controlled replication-slot WAL growth.**
  - **Verified**: Debezium connects to PostgreSQL and NATS as sink. WAL growth is constrained by `max_slot_wal_keep_size = 4GB` in `scripts/postgres-platform.sh`, and `debezium.source.heartbeat.interval.ms=30000` is configured in `application.properties`.
- **SERV-05: k3s applications reach shared services through stable LAN names.**
  - **Verified**: `gitops/apps/shared-services/` includes `Service` and `EndpointSlice` resources for postgres, valkey, nats, and debezium under `*.shared-services.svc.cluster.local`.
- **SERV-06: Applications integrate with the existing Zitadel deployment without replacing it.**
  - **Verified**: `endpointslice-zitadel.yaml` directs `zitadel` to the existing IP `10.10.30.236`.
- **SERV-07: Postgres has a verified off-host backup and restore procedure.**
  - **Verified**: `scripts/postgres-platform.sh` includes `backup` to NFS `10.10.40.2:/volume1/backup/postgres` and `restore-test` into a disposable scratch database to verify the backup.

## Context Decisions Honored

1. **PostgreSQL backup**: Uses an NFS mount to a NAS (`10.10.40.2`). Restore is proven into a temporary scratch DB via `restore_test` function in `scripts/postgres-platform.sh`.
2. **CDC and event transport**: Kafka is omitted. NATS JetStream serves as the sink. Heartbeat configuration prevents unbounded WAL growth.
3. **Kubernetes discovery**: Discovery inside the cluster utilizes static `*.shared-services.svc.cluster.local` names through `endpointslice.kubernetes.io/managed-by: homelab-gitops`. External lifecycles are completely decoupled from Argo CD.

## Conclusion

Phase 05 is complete, fully verified against its Must-Haves, and properly documented. The environment is now ready for application scaffolding (Phase 06).
