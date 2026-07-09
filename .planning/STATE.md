---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: End-to-End Homelab Deployment
current_phase: 07
current_phase_name: opt-in-public-exposure
status: complete
stopped_at: Phase 6 scaffolder gap closure complete; ready for Phase 7
last_updated: "2026-07-09T08:28:46Z"
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 28
  completed_plans: 28
  percent: 75
---

# Project State

## Current Position

Phase: 07 (opt-in-public-exposure) — READY
Status: Phase 6 scaffolder gap closure complete; Phase 7 is the next milestone step.

Phase 6 (Build Pipeline and Project Scaffolding): 06-09 closed the three
verification blockers. Non-dry-run publish now requires a GHCR pull token from
`--pull-token-file` or `GHCR_PULL_TOKEN`; plaintext `pull-secret.yaml` is mode
0600 and removed on success/failure; generated GitHub Actions GitOps push retries
now exit nonzero when all push attempts fail.

Phase 5 (Shared Stateful Services): SERV-01 through SERV-06 retain live evidence.
SERV-07 is re-closed after 05-07 hardened canonical NAS containment, exact-byte
snapshot restore behavior, remote shell argument safety, and SQL restore failure
handling. Fresh live proof restored `/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz`
with snapshot SHA-256 `e6b85d04a11a7e3508770702604a996dd8eace9f9340abdf599d42f908a30e15`.

Note: kubectl works via KUBECONFIG=.local/kubeconfig-k3s-01 (there is no ~/.kube/config).

## Deferred Verification

None.

## Session Continuity

Last session: 2026-07-07T19:07:12Z
Stopped at: Phase 5 SERV-07 verified complete; ready for Phase 7 planning/execution
Resume file: none
