---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: End-to-End Homelab Deployment
current_phase: 5
current_phase_name: Shared Stateful Services
status: blocked
stopped_at: 05-05 deployed SERV-01..04 live; SERV-05/06/07 blocked on two decisions (Argo EndpointSlice exclusion; NAS backup export)
last_updated: "2026-07-08T09:35:00.000Z"
last_activity: 2026-07-08
last_activity_desc: Deployed Phase 05 stack for real (postgres-01 + services-01), fixed 11 latent bugs, verified 4/7 SERV reqs live
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

Blocked — SERV-07 only, needs two operator infra actions I cannot perform:
1. NAS: create export 10.10.40.2:/volume1/backup/postgres allowing the Proxmox host.
2. Proxmox host: authorize the operator SSH key for root@10.10.30.30.
Host-based backup code is written + syntax-checked; run backup && restore-test to verify.

Note: kubectl works via KUBECONFIG=.local/kubeconfig-k3s-01 (there is no ~/.kube/config).

Last activity: 2026-07-08 — Deployed the stack for the first time; provisioned real
Proxmox LXC 120 + VM 121, fixed every latent bug, made k3s discovery work end-to-end.

## Session Continuity

Last session: 2026-07-07T19:07:12Z
Stopped at: Session resumed, awaiting user direction on Phase 5 planning
Resume file: none
