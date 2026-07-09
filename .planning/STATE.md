---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: End-to-End Homelab Deployment
current_phase: 08
current_phase_name: end-to-end-validation-and-operations
status: blocked
stopped_at: Phase 8 fintrack GitOps deployment synced; daemon blocked on missing runtime config
last_updated: "2026-07-09T09:22:00Z"
progress:
  total_phases: 8
  completed_phases: 7
  total_plans: 30
  completed_plans: 30
  percent: 88
---

# Project State

## Current Position

Phase: 08 (end-to-end-validation-and-operations) — BLOCKED
Status: Fintrack is registered and synced through GitOps, but the daemon is not
healthy because required runtime configuration is missing.

Phase 8 (End-to-End Validation and Operations): selected `/home/tonny/fintrack`
as the real application. Built and pushed
`ghcr.io/tkayage/fintrack:5461131698d6-20260709090701`
(`sha256:77f436a929c9695156610fd1a116e067571ae2a537782d5fe61dbbd90473d6c5`),
committed GitOps registration `473fb41 deploy(fintrack): register daemon app`,
rotated the stale in-cluster Argo GitOps repository credential, and proved Argo
discovered/synced `Application/fintrack`. Kubernetes created the PVC/secrets,
pulled the private GHCR image, and started the container. The pod is in
CrashLoopBackOff with `missing required env var: CLOUDFLARE_API_TOKEN` because
real fintrack runtime values were not present in `/home/tonny/fintrack`,
`/home/tonny/.config/homelab`, or the process environment.

Phase 7 (Opt-in Public Exposure): default-deny public exposure is implemented.
Generated apps are LAN-only unless `--public` is set; public DNS metadata is
per-host only; `scripts/public-edge.sh` verified Cloudflare preflight,
default-deny for `edge-smoke.app.kayage.co`, and admin-surface non-exposure.
Full public enable/reach/disable is deferred to the Phase 8 validation app.

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

Phase 8 cannot close until real fintrack runtime values are supplied and
`apps/fintrack/runtime-secret.enc.yaml` is updated:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `CF_QUEUE_ID`
- `SURE_URL`
- `SURE_API_KEY`
- `ALERT_FROM`
- `ALERT_TO`

After that, rerun rollout/log verification and complete the rollback plus MS-01
restart recovery exercises.

## Session Continuity

Last session: 2026-07-07T19:07:12Z
Stopped at: Phase 5 SERV-07 verified complete; ready for Phase 7 planning/execution
Resume file: none
