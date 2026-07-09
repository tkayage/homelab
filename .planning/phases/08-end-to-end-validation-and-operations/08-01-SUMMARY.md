---
phase: 08-end-to-end-validation-and-operations
plan: 01
subsystem: fintrack-deployment
tags: [gitops, ghcr, daemon, running]
key-files:
  - .planning/phases/08-end-to-end-validation-and-operations/08-CONTEXT.md
  - .planning/phases/08-end-to-end-validation-and-operations/08-01-PLAN.md
  - .planning/phases/08-end-to-end-validation-and-operations/08-VERIFICATION.md
  - docs/runbooks/fintrack-deployment.md
metrics:
  tests: "go test ./...; python3 -m pytest -q"
---

# 08-01 Summary: Fintrack Deployment

## Commits

| Commit | Scope | Description |
|--------|-------|-------------|
| `473fb41` | gitops-homelab | Registered `apps/fintrack` as an outbound-only daemon Deployment with PVC, GHCR pull secret, and runtime secret. |
| `3e74e46` | gitops-homelab | Replaced the encrypted runtime Secret with real fintrack configuration. |

## What Changed

- Added Phase 8 context and plan selecting `/home/tonny/fintrack`.
- Built and pushed `ghcr.io/tkayage/fintrack:5461131698d6-20260709090701`.
- Added GitOps manifests under `.local/gitops-homelab/apps/fintrack`.
- Rotated the in-cluster Argo repo credential after ApplicationSet failed to list refs.
- Wrote `docs/runbooks/fintrack-deployment.md`.

## Verification

- `go test ./...` passed in `/home/tonny/fintrack`.
- `python3 -m pytest -q` passed in `/home/tonny/fintrack`.
- Docker build and GHCR push succeeded.
- SOPS decrypt plus `kustomize build` simulation passed.
- Argo discovered and synced `Application/fintrack`.
- Kubernetes pulled the private GHCR image.
- After runtime config was added, Kubernetes rolled out a `1/1 Running` pod.
- Startup logs show allowlist load, Sure account validation, dedupe DB open, alert sender configuration, and polling startup.

## Deviations

- Fintrack is not a web application. No Service, Ingress, valid-TLS URL, public
  routing, Postgres, or Zitadel integration was added.
- Full Phase 8 recovery exercises remain outside this deployment slice.

## Self-Check: PASSED

The fintrack daemon is deployed end to end and healthy through GitOps. Phase 8
still has broader rollback and restart recovery work before the milestone can be
closed.
