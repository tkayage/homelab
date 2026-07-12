# Architecture Research: v1.1 Scaffolder CLI Service

**Domain:** Homelab GitOps scaffolder integration
**Researched:** 2026-07-12
**Confidence:** HIGH for repository-specific integration points; MEDIUM for exact CLI UX until phase discussion finalizes commands and prompts.

## Executive Summary

v1.1 should extend the existing Go scaffolder as the single operator entrypoint for both onboarding and updating services. Do not add an imperative deploy path and do not add a separate "service updater" binary. The current deployment architecture is already settled: app repos build GHCR images, `gitops-homelab` is the Kubernetes desired-state source, Argo CD discovers `apps/*`, and SOPS-encrypted YAML is decrypted by the existing Argo CMP before Kustomize runs.

The architectural change is a mode split inside the scaffolder orchestration: create mode renders a new app repo workflow plus a new GitOps app directory; update mode loads an existing `apps/<slug>/` service, applies targeted mutations, encrypts any changed secret material, validates the rendered Kustomize tree, and commits through the same GitOps repository flow. Existing service directories must be treated as owned state, not disposable template output.

The most important design constraint is preservation. Existing services may not match the generic web-app template. The live `fintrack` service already has daemon-only shape, a PVC, runtime config secret, mounted secret file, and no Service/Ingress. v1.1 update flows must parse and patch specific Kubernetes resources rather than re-rendering the whole directory from `internal/manifests`.

## Current Architecture Anchors

| Anchor | Current Shape | v1.1 Implication |
|--------|---------------|------------------|
| `scaffold/cmd/scaffold/main.go` | Cobra root delegates to one `scaffolder.Run` path. | Keep one installed binary; add explicit commands or modes under the same root. |
| `scaffold/internal/scaffolder` | Orchestrates preflight, repo root, slug, detection, app files, GitOps publish, report. | Split orchestration into create/update workflows sharing preflight, slug, GitOps sync, validation, and reporting. |
| `scaffold/internal/detect` | T3-first detection, non-T3 requires an existing Dockerfile. | Replace with Dockerfile-first detection; missing Dockerfile becomes a generation offer, not an immediate hard failure. |
| `scaffold/internal/gitops` | Clones/syncs `gitops-homelab`, renders `apps/<slug>/`, encrypts pull secret, commits/pushes. | Generalize from "publish rendered app" to "open worktree, mutate app dir, encrypt changed secrets, commit/push if changed." |
| `scaffold/internal/manifests` | Full template renderer for a new web app manifest set. | Keep for create mode only. Do not use it to update existing services. |
| `.local/gitops-homelab/apps/*` | Argo ApplicationSet discovers every app directory and deploys via `sops-kustomize-v1.0`. | Update mode changes only files under one `apps/<slug>/` directory, preserving automatic Argo adoption. |
| `.local/gitops-homelab/.sops.yaml` | `*.enc.yaml` files encrypt `data`/`stringData` with the platform age recipient. | Secret update path must emit `runtime-secret.enc.yaml` or update existing secret ciphertext with the same convention. |

## Recommended Architecture

```
dev server
  scaffold binary
    preflight: git, sops, kustomize, credentials
    resolve: app repo root, slug, gitops worktree
    detect: Dockerfile-first project shape
    plan: create vs update, dry-run diff, prompt decisions
    mutate app repo: Dockerfile generation, workflow generation
    mutate gitops repo:
      create mode -> render initial app directory
      update mode -> load existing app directory and patch resources
    validate: SOPS decrypt simulation, kustomize build, kubectl dry-run when available
    commit: git add apps/<slug>, commit, push
    report: files changed, commit sha, Argo app, warnings
```

### Component Boundaries

| Component | Status | Responsibility | Notes |
|-----------|--------|----------------|-------|
| CLI root and commands | Modified | Installed binary entrypoint, flags, prompts, command routing. | Prefer explicit commands: `scaffold create` and `scaffold update`; keep bare `scaffold` as create-compatible alias if needed. |
| `scaffolder` orchestrator | Modified | Coordinates create/update workflows and shared report shape. | Introduce a workflow-level plan object before writes so dry-run and prompts are consistent. |
| Dockerfile detector | Modified | Dockerfile-first detection, EXPOSE parsing, non-root warning, optional generation. | T3/Next detection becomes advisory for generated Dockerfile/health route selection, not the primary gate. |
| Dockerfile generator | New or expanded templates | Generate a Dockerfile when missing and operator confirms. | Keep generation conservative; never overwrite an existing Dockerfile without explicit future force semantics. |
| GitOps worktree manager | Modified | Credential loading, push preflight, clone/pull/rebase, scoped commit/push. | Extract reusable `SyncWorktree`, `CommitIfChanged`, and app-dir helpers from current `Publish`. |
| GitOps service loader | New | Read `apps/<slug>/kustomization.yaml`, discover resource files, parse Deployments/Secrets. | Needed for update mode; prevents template overwrite of daemon/custom services. |
| Manifest patcher | New | Apply targeted changes to Deployment env/envFrom, Kustomization resources, runtime Secret. | Use YAML-aware patching, not string replacement. Preserve unknown fields and file ordering where practical. |
| Secret manager | New | Decrypt existing `*.enc.yaml`, merge secret keys, re-encrypt, assert no plaintext remains. | Must support create/update of runtime secrets separately from the GHCR pull secret. |
| Validation runner | Modified | Existing offline proof plus update-flow validation. | Add tests for decrypt -> kustomize build -> kubectl dry-run after env/secret updates. |
| Report package | Modified | Print create/update result with changed files, commit sha, and warnings. | Existing report shape is create-biased; update needs changed keys and validation status. |

## Data Flow Changes

### Create Flow

```
operator runs scaffold create in app repo
  -> resolve slug and Dockerfile status
  -> if Dockerfile exists: validate and parse port
  -> if missing: offer to generate Dockerfile, then parse generated port
  -> render app workflow
  -> render new apps/<slug>/ GitOps directory
  -> encrypt GHCR pull secret
  -> validate kustomization
  -> commit/push gitops main
  -> Argo ApplicationSet discovers apps/<slug>
```

This is the current Phase 6 flow with Dockerfile-first detection and a controlled missing-Dockerfile branch.

### Existing Service Update Flow

```
operator runs scaffold update --slug <slug> [--env KEY=VALUE] [--secret KEY=VALUE]
  -> sync gitops worktree
  -> assert apps/<slug>/ exists
  -> load kustomization resources
  -> find primary Deployment or ask when ambiguous
  -> patch non-secret env under containers[*].env
  -> decrypt or create runtime-secret.yaml from runtime-secret.enc.yaml
  -> merge secret values into stringData/data
  -> ensure Deployment references runtime secret via envFrom or volume as requested
  -> re-encrypt runtime secret to runtime-secret.enc.yaml
  -> remove plaintext
  -> validate decrypt+kustomize build
  -> commit/push gitops main
  -> Argo reconciles normal GitOps change
```

Update mode must not touch the app repo unless the operator is also generating a Dockerfile or workflow. Env and secret updates for existing services are GitOps-only changes.

## New vs Modified Decisions

### Modify

- **Modify `detect.Detect` semantics:** look for Dockerfile first, including `--dockerfile`; parse `EXPOSE`; warn on root containers. Then optionally inspect package metadata to choose helper behavior such as Next health route generation.
- **Modify `gitops.Publish`:** split into lower-level worktree and commit primitives. Keep the current create/publish function as a wrapper for backwards compatibility during refactor.
- **Modify `manifests.Data`:** only for new app creation if env/secrets need initial support. Do not force existing services through this struct.
- **Modify generated workflow only when creating or explicitly regenerating app repo files.** Existing-service env/secret updates should not rewrite `.github/workflows/deploy.yml`.
- **Modify tests and `scripts/scaffold-verify.sh`:** add update fixtures that start from an existing GitOps app directory and prove patch/encrypt/validate/commit behavior.

### Add

- **Add `internal/gitops/service` or `internal/gitops/appdir`:** app directory discovery and resource loading.
- **Add `internal/kube` or `internal/patch`:** typed or YAML-node patch helpers for Deployment env and kustomization resource edits.
- **Add `internal/secrets`:** SOPS decrypt/merge/encrypt for runtime secrets, separate from GHCR pull-secret code.
- **Add CLI update command:** accepts non-secret env additions and secret additions without app repo assumptions.
- **Add Dockerfile generation prompts/templates:** missing Dockerfile path must be explicit and reviewable before writing.
- **Add dry-run diff output:** especially important for update mode because the target is existing GitOps-managed state.

### Do Not Add

- No in-cluster controller for scaffolder operations.
- No direct Kubernetes mutation as the source of truth.
- No second GitOps repo or per-service registry of app metadata.
- No full directory re-render for existing service updates.
- No plaintext secret files committed or left in the worktree after failures.

## Manifest Patching Model

Use structured YAML parsing with round-trip preservation where available in Go. The update target should be Kubernetes object identity, not filename assumptions:

| Operation | Target | Rule |
|-----------|--------|------|
| Non-secret env var | Deployment container `env` | Upsert by `name`; replace existing value only after explicit confirmation or flag. |
| Runtime secret env | Secret `stringData` or `data` | Decrypt existing `runtime-secret.enc.yaml` if present; otherwise create `runtime-secret.yaml`, add to kustomization as `runtime-secret.yaml`, then encrypt. |
| Secret reference | Deployment `envFrom.secretRef` | Add only when missing and only for env-style secrets. Do not add `envFrom` for file-mounted secrets without explicit volume options. |
| Kustomization | `resources` | Reference decrypted filename, e.g. `runtime-secret.yaml`, while committed file remains `runtime-secret.enc.yaml`. |
| Existing pull secret | `pull-secret.enc.yaml` | Leave alone unless updating GHCR pull credentials is explicitly requested. |

The `fintrack` shape proves why this matters: it has runtime secrets both as environment and as a mounted file, plus a PVC and custom container name. A generic app template would destroy valid service-specific configuration.

## Build Order Recommendation

1. **Refactor GitOps primitives first**
   - Extract sync, credential, stage, commit, push, changed-files, and app-dir path helpers from `gitops.Publish`.
   - Verification gate: existing create tests and `scripts/scaffold-verify.sh all` still pass unchanged.

2. **Implement service loader and read-only inspect command**
   - Load `apps/<slug>/kustomization.yaml`, enumerate resources, identify Deployments and encrypted secrets.
   - Verification gate: inspect works against fixture app dirs and live-shaped `fintrack` fixture without writing.

3. **Replace detection with Dockerfile-first behavior**
   - Preserve EXPOSE parsing and warnings; add missing-Dockerfile result that the CLI can turn into a prompt.
   - Verification gate: existing Dockerfile fixtures pass; T3 fixture still gets appropriate generated helper behavior.

4. **Add Dockerfile generation when missing**
   - Add prompt/flag path and conservative templates. Never overwrite existing Dockerfile.
   - Verification gate: missing-Dockerfile fixture creates expected Dockerfile and still validates through build/kustomize dry-run.

5. **Add non-secret env update**
   - Patch Deployment env in existing app dirs with no secret handling yet.
   - Verification gate: update fixture preserves unrelated Deployment fields, PVCs, Ingress absence/presence, and custom resources.

6. **Add runtime secret update**
   - Decrypt, merge, re-encrypt, update kustomization resource references, assert no plaintext remains.
   - Verification gate: SOPS round-trip, no plaintext committed, `kustomize build` after CMP simulation, and `kubectl apply --dry-run`.

7. **Wire final CLI UX and reports**
   - Stabilize command names, prompts, dry-run diff, and completion output.
   - Verification gate: operator-facing report shows changed app dir, env keys, secret key names only, commit sha, and validation results.

This order reduces risk by proving the GitOps mutation substrate before adding writes, then adding plaintext env patching before secret mutation.

## Requirement Implications

| Requirement Area | Implication |
|------------------|-------------|
| CLI binary install/run | Add a packaging/install step for the existing Go module, likely building to a dev-server PATH location. The binary remains source-built from this repo unless module publishing becomes a separate requirement. |
| Dockerfile-first detection | Update SCAF-06 semantics: Dockerfile is the primary containerization contract; framework detection is secondary convenience. |
| Generate Dockerfile when missing | New requirement should include non-overwrite and operator confirmation criteria. |
| Update existing GitOps services | New requirement must define preservation: updates must only mutate requested fields under `apps/<slug>/`. |
| Non-secret env updates | Require deterministic upsert behavior, duplicate-key detection, and validation of resulting Deployment YAML. |
| Encrypted secret updates | Require decrypt/merge/encrypt flow, no plaintext commit, secret key names in reports without values, and kustomization references to decrypted filenames. |
| Commit through GitOps flow | Reuse current push preflight and commit/push path; updates are normal GitOps commits, not cluster commands. |

## Pitfalls to Avoid

| Pitfall | Consequence | Prevention |
|---------|-------------|------------|
| Re-rendering existing app directories | Deletes daemon/PVC/secret mount/custom resource shape. | Load and patch existing YAML resources. |
| Treating secret ciphertext as editable YAML data | Corrupts SOPS files or loses keys. | Decrypt to temporary plaintext, merge, re-encrypt, remove plaintext before staging. |
| Referencing `.enc.yaml` in kustomization | Argo CMP decrypts to `.yaml`; Kustomize expects decrypted filenames. | Always list `runtime-secret.yaml`, not `runtime-secret.enc.yaml`. |
| Updating live Kubernetes directly | Breaks GitOps source-of-truth and rollback history. | All updates commit to `gitops-homelab`. |
| Assuming every service is a web app | Daemon services like `fintrack` have no Service/Ingress. | Resource discovery must tolerate absent Service/Ingress. |
| Hiding update diffs | Operator may overwrite env or secret keys accidentally. | Provide dry-run and explicit replacement behavior. |

## Sources

- `.planning/PROJECT.md` - v1.1 milestone scope and active requirements.
- `.planning/REQUIREMENTS.md` - validated v1.0 GitOps, scaffolding, secrets, and edge constraints.
- `scaffold/internal/scaffolder/scaffolder.go` - current end-to-end orchestration.
- `scaffold/internal/detect/detect.go` - current T3-first and Dockerfile parsing behavior.
- `scaffold/internal/gitops/gitops.go` and `scaffold/internal/gitops/sops.go` - current GitOps commit and SOPS encryption flow.
- `scaffold/internal/manifests/manifests.go` and `scaffold/internal/templates/files/gitops/*` - current new-app manifest rendering model.
- `.local/gitops-homelab/platform/applicationset.yaml` - Argo CD `apps/*` discovery and CMP integration.
- `.local/gitops-homelab/.sops.yaml` - SOPS creation rules.
- `.local/gitops-homelab/apps/fintrack/*` - existing-service shape that must be preserved.
- `scripts/scaffold-verify.sh` - current offline verification pattern to extend for update flows.
