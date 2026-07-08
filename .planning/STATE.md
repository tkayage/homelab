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
Plan: 05-05 — Deploy and validate shared services (partial: 4/7 SERV live, 3 blocked)
Status: Blocked on two decisions

Live and verified: postgres-01 (LXC 120), Valkey, NATS/JetStream, Debezium all
running/healthy; CDC pipeline proven (SERV-01..04). 11 latent IaC/script bugs fixed
during first-ever deployment (see 05-05-SUMMARY.md).

Blocked — awaiting user decision:
- SERV-05/06 (k8s discovery): Argo CD argocd-cm excludes EndpointSlice → selectorless
  Services have no backends. Fix = un-exclude EndpointSlice in argocd-cm (Phase 3
  platform config) OR create slices out-of-band. Mechanism proven via manual slice.
- SERV-07 (backup): NFS export /volume1/backup/postgres absent on NAS (only
  /volume1/surveillance → Proxmox host exists) + in-container NFS mount unviable.
  Needs NAS export + backup-host/design decision.

Last activity: 2026-07-08 — Deployed the stack for the first time; provisioned real
Proxmox LXC 120 + VM 121, fixed every latent bug, published shared-services to Argo.

## Session Continuity

Last session: 2026-07-07T19:07:12Z
Stopped at: Session resumed, awaiting user direction on Phase 5 planning
Resume file: none
