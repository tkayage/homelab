# Phase 6: Build Pipeline and Project Scaffolding - Context

**Gathered:** 2026-07-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the "one command + git push → live app" pipeline. A Go scaffolder run once in
an app repo generates the build/deploy plumbing (Dockerfile, GitHub Actions workflow,
and per-app GitOps manifests committed to `tkayage/gitops-homelab`); thereafter every
push to `main` builds a versioned private GHCR image, CI bumps the image reference in
the GitOps repo, and Argo CD reconciles it to a valid-TLS URL. Covers GITOPS-03/04 and
SCAF-01..06. Public exposure (Phase 7) and the real end-to-end validation app (Phase 8)
are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Scaffolder (form & contract)
- Written in **Go** — single static binary, no runtime deps, cross-platform CLI. (User
  chose Go over Node/TS and Bash.)
- Runs **in-place** inside an existing app repo; adds a Dockerfile, a GitHub Actions
  workflow, and registers the app's GitOps manifests. New-project generation is deferred.
- Commits the app's manifests **directly to `apps/<slug>/` in `tkayage/gitops-homelab`**
  (the ApplicationSet source), decoupled from this platform repo.
- **One canonical slug** drives everything: derive from the repo/dir name, validate
  `^[a-z][a-z0-9-]{1,30}$`, `--slug` override. Slug → image `ghcr.io/tkayage/<slug>`,
  namespace `<slug>`, host `<slug>.app.kayage.co`, gitops dir `apps/<slug>`.

### Image build & CI
- **GitHub Actions**, triggered on **push to `main`** → build → push → bump gitops.
- Immutable primary tag = **short git SHA** (`ghcr.io/tkayage/<slug>:sha-<short>`) plus a
  moving `latest`; GitOps pins the SHA tag for deterministic reconciliation.
- **Generate a proven multi-stage T3/Next standalone Dockerfile**; for non-T3 repos,
  **detect and validate an existing Dockerfile** rather than overwriting it (SCAF-06).

### Deploy wiring
- CI **bumps the image ref by committing to gitops-homelab** — `kustomize edit set image
  ghcr.io/tkayage/<slug>=...:sha-<short>` in `apps/<slug>/`, commit + push `main`; Argo
  auto-syncs. Git stays the source of truth; no in-cluster image-updater controller.
- CI authenticates to the private gitops repo with a **fine-grained PAT or deploy key**
  stored as a GitHub Actions secret (final choice at planning; solo-operator simple).
- **Private GHCR** images. Each app carries a **per-app SOPS `pull-secret.enc.yaml`**
  (dockerconfigjson) decrypted by the existing `sops-kustomize-v1.0` CMP plugin and
  referenced via `imagePullSecrets` — reuses the Phase 3 SOPS+age pattern.

### Workload shape, health & reporting
- Per-app manifests mirror the `edge-smoke` exemplar: **Deployment, Service, Ingress
  (`<slug>.app.kayage.co`, ingressClassName traefik), pull-secret.enc.yaml, and a
  kustomization.yaml with an `images:` block**; the namespace is auto-created by the
  ApplicationSet (`CreateNamespace=true`).
- Health: **readiness + liveness `httpGet /api/health`** for T3 (scaffolder adds the
  route); **TCP probe on the container port** for non-T3, overridable.
- Defaults: **1 replica, container port 3000 (Next default), bounded CPU/memory
  requests+limits, RollingUpdate.**
- Scaffolder **reports** (SCAF-05): generated files, the gitops commit it pushed, the
  expected URL `https://<slug>.app.kayage.co`, and the Argo application name + how to
  check health.

### Claude's Discretion
- Go module layout and binary name, template-engine usage (`text/template` + `embed`),
  exact Dockerfile base-image pins and stages, GitHub Actions action versions, the final
  PAT-vs-deploy-key pick, and the T3 health-route implementation follow current best
  practices and existing repo conventions.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`gitops/apps/edge-smoke/`** — the closest analog: Deployment + Service + Ingress
  (`edge-smoke.app.kayage.co`) + kustomization. Copy its shape for scaffolded apps.
- **`gitops/platform/applicationset.yaml`** (`homelab-apps`) — git-directory generator
  over `apps/*` in `github.com/tkayage/gitops-homelab.git@main`; namespace =
  `{{path.basenameNormalized}}`; CMP plugin `sops-kustomize-v1.0`; automated sync with
  prune + selfHeal + `CreateNamespace=true`. A new `apps/<slug>/` dir is auto-adopted.
- **`gitops/apps/gitops-smoke/secret.enc.yaml`** + **`gitops/.sops.yaml`** — the SOPS+age
  secret pattern: `*.enc.yaml`, `encrypted_regex ^(data|stringData)$`, age recipient
  `age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq`. Model the GHCR
  pull-secret on this.
- **`scripts/gitops-platform.sh`** — shows the gitops-homelab push flow (clone at
  `.local/gitops-homelab`, `GITOPS_REPO=tkayage/gitops-homelab`, push-permission check,
  commit+push main) and how GitHub creds from `github.env` are used.

### Established Patterns
- Platform automation is bash `scripts/*-platform.sh`; versions/downloads pinned; external
  credentials live in `/home/tonny/.config/homelab/*.env` (github.env) and never enter git.
- Argo owns in-cluster objects; external lifecycles stay outside Argo.

### Integration Points
- Image registry org: **`ghcr.io/tkayage`**. GitOps repo: **`tkayage/gitops-homelab@main`**.
- Edge: `*.app.kayage.co` via NPM (`10.10.30.237`) → Traefik (`10.10.30.102`), wildcard TLS.
- Shared services reachable at `*.shared-services.svc.cluster.local`; Zitadel at
  `zitadel.kayage.co` (used later by the Phase 8 validation app).

</code_context>

<specifics>
## Specific Ideas

- Apps are primarily **T3 (TypeScript/Next.js)** but the contract must stay app-agnostic
  (any containerizable repo) — SCAF-06.
- The scaffolder is the **only** per-project manual step; everything after is git-push +
  GitOps.
- No existing CI or scaffolding in the repo — Phase 6 builds both from scratch.

</specifics>

<deferred>
## Deferred Ideas

- New-project generation from a T3 template (`--new`) — scaffolder is in-place only for v1.
- Argo CD Image Updater and reflector-based shared pull secrets — chose CI-writes-git +
  per-app SOPS instead.
- Public exposure (Phase 7); the real end-to-end validation app (Phase 8).
- Staging environments / promotion and per-app Postgres/OIDC auto-provisioning — future
  milestone (OPS-02, DX-01, DX-05).

</deferred>
