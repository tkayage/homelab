---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: End-to-End Homelab Deployment
current_phase: 5
current_phase_name: Shared Stateful Services
status: blocked
stopped_at: 05-05 SERV-01..06 live; SERV-07 restore live-verified into disposable scratch instance, blocked only on one NAS grant (rw for workstation 10.10.30.70 on /volume1/homelab-backups)
last_updated: "2026-07-08T11:40:00.000Z"
last_activity: 2026-07-08
last_activity_desc: Reworked SERV-07 to workstation-mediated backup; live-verified restore into a disposable postgres:17 scratch container; fixed unsafe restore-into-live-server bug; one NAS grant remains
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 17
  completed_plans: 16
  percent: 50
---

# Project State

## Current Position

Phase: 5 — Shared Stateful Services (reopened 2026-07-08)
Plan: 05-05 — Deploy and validate shared services (6/7 SERV live; SERV-07 blocked)
Status: Blocked on SERV-07 operator prerequisites only

Live and verified (SERV-01..06): postgres-01 (LXC 120), Valkey, NATS/JetStream,
Debezium all healthy; CDC pipeline proven; k3s discovery + Zitadel OIDC pass the live
test (all 5 EndpointSlices Argo-managed after un-excluding EndpointSlice in argocd-cm).
12 latent IaC/script bugs fixed during the first-ever deployment (see 05-05-SUMMARY.md).

Blocked — SERV-07 only, now ONE operator action (down from two). Backup reworked to
workstation-mediated (Proxmox-host approach retired: 10.10.30.30 has no reachable shell,
and the unprivileged LXC can't mount NFS). RESTORE IS LIVE-VERIFIED — a real pg_dumpall
from the LXC restores cleanly into a disposable postgres:17 scratch container on
services-01 (debezium role + dbz_publication reconstructed, then torn down). Only the
off-host NAS write remains:
  → NAS: grant the workstation 10.10.30.70 read/write NFS access to
    10.10.40.2:/volume1/homelab-backups (folder exists; export currently denies it).
Then: scripts/postgres-platform.sh backup && scripts/postgres-platform.sh restore-test.

Note: kubectl works via KUBECONFIG=.local/kubeconfig-k3s-01 (there is no ~/.kube/config).

Last activity: 2026-07-08 — Deployed the stack for the first time; provisioned real
Proxmox LXC 120 + VM 121, fixed every latent bug, made k3s discovery work end-to-end.

## Session Continuity

Last session: 2026-07-07T19:07:12Z
Stopped at: Session resumed, awaiting user direction on Phase 5 planning
Resume file: none
