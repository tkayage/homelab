---
phase: 08-end-to-end-validation-and-operations
status: passed
date: 2026-07-12
score: 4/5
deferred_verification:
  - id: OPS-MS01-RESTART
    original_requirement: E2E-04
    reason: "MS-01 host restart is intentionally disruptive and was explicitly deferred from v1.0 closure."
    expected: "After MS-01 restart, Proxmox guests return in dependency order and fintrack/Argo/shared services recover without manual app rewiring."
---

# Phase 8 Verification

## Result

Fintrack deployment is live and healthy for the selected outbound-only daemon.
GitOps failed-rollout visibility and git-revert recovery are proven. Phase 8 is
complete for the selected validation slice. The MS-01 restart recovery exercise
is explicitly deferred to future operations work because that action
intentionally disrupts the host and was not required for closing v1.0.

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
- Bad rollout proof commit: `66e7c2f test(fintrack): simulate bad image rollout`
- Recovery commit: `6c98800 Revert "test(fintrack): simulate bad image rollout"`
- App path: `.local/gitops-homelab/apps/fintrack`
- CMP simulation passed: decrypt `*.enc.yaml` to `*.yaml`, then `kustomize build`.
- Static exposure scan passed: no `Service`, `Ingress`, public marker, or
  `external-dns` annotation exists under `apps/fintrack`.
- Argo repository credential was rotated because the existing in-cluster
  credential produced `authentication required`.
- Argo discovered `Application/fintrack`.
- Argo status after runtime secret sync: `Synced Progressing`.
- Argo status after rollback recovery: `Synced Healthy` at revision
  `6c988009155ce314981e7f11bc7aa431edd4d722`.

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
- 2026-07-12 recheck: Argo reports `fintrack` as `Synced` / `Healthy` at
  revision `6c988009155ce314981e7f11bc7aa431edd4d722`; the Deployment is
  `1/1` available, the pod is `1/1 Running`, the PVC is bound, and logs show
  active polling.
- Startup logs:
  - `allowlist loaded from file /config/allowlist.json: 5 entries across banks map[crdb:2 mpesa:1 selcom:1 yas:1]`
  - `startup OK: 5 allowlist entries validated against 7 Sure accounts`
  - `dedupe store opened at /data/dedupe.db; alerter configured ... Token:[REDACTED]`
  - `fintrack daemon started; polling every 5s`

### Rollback Proof

- Baseline: `Application/fintrack` was `Synced Healthy`, Deployment `1/1`, pod
  `1/1 Running`.
- Committed and pushed `66e7c2f test(fintrack): simulate bad image rollout`,
  changing the image to `ghcr.io/tkayage/fintrack:rollback-proof-missing`.
- Argo reconciled the bad commit and reported `Synced Progressing`.
- Kubernetes created `ReplicaSet/fintrack-5587c696d5` and pod
  `fintrack-5587c696d5-69p6t`, which failed with `ErrImagePull` /
  `ImagePullBackOff` because the tag does not exist.
- The previous healthy pod `fintrack-55d98b7969-fx4hs` stayed `1/1 Running`
  during the failed rollout.
- Reverted the bad commit with `6c98800`.
- Argo reconciled the revert and returned to `Synced Healthy`.
- Deployment returned to image
  `ghcr.io/tkayage/fintrack:5461131698d6-20260709090701`; the bad ReplicaSet
  scaled to zero and the healthy ReplicaSet remained ready.

## Requirement Status

- E2E-01: Satisfied for the selected daemon. GitOps deployment, private image
  pull, healthy pod rollout, and daemon startup are proven. Valid-TLS URL is
  not applicable because fintrack intentionally has no listener.
- E2E-02: Not applicable to this selected service. Fintrack does not use
  Postgres or Zitadel. This selected-app mismatch is documented instead of
  adding fake dependencies.
- E2E-03: VERIFIED. A bad image deployment was visible through Argo and
  Kubernetes, and `git revert` restored `Synced Healthy` state.
- E2E-04: DEFERRED. MS-01 restart recovery remains valid future operations debt,
  but is explicitly out of the Phase 8 completion gate.
- E2E-05: Satisfied for the selected daemon. Fintrack deployment, diagnosis,
  rollback, and recovery notes exist at `docs/runbooks/fintrack-deployment.md`;
  broader platform recovery documentation remains future operations work.

## Deferred Operations Work

- Execute the MS-01 restart recovery exercise during an operator-approved
  maintenance window.
- Broaden the runbook beyond fintrack-specific deployment if future milestones
  require full-platform disaster-recovery reproducibility.
