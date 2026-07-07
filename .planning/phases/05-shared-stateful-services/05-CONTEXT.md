---
phase: 05-shared-stateful-services
status: discussed
date: 2026-07-07
---

# Phase 5 Context

## Phase boundary

Provision the Phase 1-defined PostgreSQL LXC and shared-services Compose VM, configure recoverable bounded services, expose stable in-cluster names, integrate existing Zitadel, and prove off-host PostgreSQL restore. Application scaffolding remains Phase 6.

## Decisions

### PostgreSQL backup

- Store logical PostgreSQL backups on the existing NAS at `10.10.40.2`, not on Proxmox local storage.
- Use a dedicated NFS export; do not introduce SMB credentials.
- Prove a real restore into a disposable scratch database/instance before completion.

### CDC and event transport

- Run Debezium Server with NATS JetStream as its sink.
- Kafka is explicitly excluded; adding it would exceed the approved service and capacity boundary.
- Configure PostgreSQL slot WAL bounds and Debezium heartbeat behavior so a stopped/idle consumer cannot grow WAL without limit.

### Kubernetes discovery

- Expose PostgreSQL, Valkey, NATS, Debezium, and existing Zitadel through GitOps-managed selectorless Services plus EndpointSlices.
- Applications consume stable `*.shared-services.svc.cluster.local` names rather than LAN IPs or Mikrotik DNS directly.
- External service lifecycle remains outside Argo CD; Argo owns only the in-cluster discovery objects and connection-test workload.

## Existing allocations

- `postgres-01`: LXC 120, `10.10.30.100`, 2 vCPU, 4096 MiB, 64 GiB, startup order 10.
- `services-01`: VM 121, `10.10.30.101`, 4 vCPU, 8192 MiB, 64 GiB, startup order 20.
- Existing Zitadel: `10.10.30.236`, valid TLS at `zitadel.kayage.co`; retain without replacement.

## Safety

- Generate database/service credentials outside git and commit only SOPS ciphertext where Kubernetes consumers need them.
- Apply explicit Valkey memory, NATS file-store, and container resource limits.
- Never treat a Proxmox snapshot as the PostgreSQL backup.
