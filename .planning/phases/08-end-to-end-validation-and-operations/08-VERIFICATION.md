---
phase: 08-end-to-end-validation-and-operations
status: blocked
date: 2026-07-09
---

# Phase 8 Verification

## Result

Fintrack deployment is live and healthy for the selected outbound-only daemon.
Phase 8 remains open for the broader recovery exercises: full GitOps rollback
proof and MS-01 restart recovery have not been executed.

## Evidence

### Source and Build

- `/home/tonny/fintrack` worktree was clean on `master`.
- `go test ./...` passed.
- `python3 -m pytest -q` passed: 86 tests passed, 16 warnings.
- Docker image built from `/home/tonny/fintrack/deploy/Dockerfile`.
- Pushed image: `ghcr.io/tkayage/fintrack:5461131698d6-20260709090701`
- Digest: `sha256:77f436a929c9695156610fd1a116e067571ae2a537782d5fe61dbbd90473d6c5`

### GitOps

- GitOps commit: `473fb41 deploy(fintrack): register daemon app`
- Runtime secret commit: `3e74e46 deploy(fintrack): configure runtime secret`
- App path: `.local/gitops-homelab/apps/fintrack`
- CMP simulation passed: decrypt `*.enc.yaml` to `*.yaml`, then `kustomize build`.
- Static exposure scan passed: no `Service`, `Ingress`, public marker, or
  `external-dns` annotation exists under `apps/fintrack`.
- Argo repository credential was rotated because the existing in-cluster
  credential produced `authentication required`.
- Argo discovered `Application/fintrack`.
- Argo status after runtime secret sync: `Synced Progressing`.

### Cluster

- Namespace resources created:
  - `Deployment/fintrack`
  - `PersistentVolumeClaim/fintrack-data`
  - `Secret/fintrack-runtime`
  - `Secret/ghcr-pull`
- PVC bound through local-path.
- Pod pulled the private GHCR image successfully.
- After `runtime-secret.enc.yaml` was updated from
  `/home/tonny/.config/homelab/fintrack.env`, the replacement pod rolled out.
- Current pod state: `1/1 Running`.
- Startup logs:
  - `allowlist loaded from file /config/allowlist.json: 5 entries across banks map[crdb:2 mpesa:1 selcom:1 yas:1]`
  - `startup OK: 5 allowlist entries validated against 7 Sure accounts`
  - `dedupe store opened at /data/dedupe.db; alerter configured ... Token:[REDACTED]`
  - `fintrack daemon started; polling every 5s`

## Requirement Status

- E2E-01: Satisfied for the selected daemon. GitOps deployment, private image
  pull, healthy pod rollout, and daemon startup are proven. Valid-TLS URL is
  not applicable because fintrack intentionally has no listener.
- E2E-02: Not applicable to this selected service. Fintrack does not use
  Postgres or Zitadel. This selected-app mismatch is documented instead of
  adding fake dependencies.
- E2E-03: Partially satisfied. The initial failed deployment was visible through
  Argo and Kubernetes. Full rollback exercise remains open.
- E2E-04: Not executed. MS-01 restart recovery remains open.
- E2E-05: Partially satisfied. Fintrack deployment runbook exists at
  `docs/runbooks/fintrack-deployment.md`; broader platform recovery runbook
  remains open.

## Remaining Phase Work

- Prove a bad GitOps deployment is recovered through git revert.
- Execute or explicitly defer the MS-01 restart recovery exercise.
- Broaden the runbook beyond fintrack-specific deployment if Phase 8 is expected
  to close the full milestone operations requirement.
