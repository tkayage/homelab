# Phase 6: Build Pipeline and Project Scaffolding - Research

**Researched:** 2026-07-08
**Domain:** Go CLI tooling, GitHub Actions CI → GHCR, GitOps image promotion (Argo CD + Kustomize + SOPS)
**Confidence:** HIGH for the codebase-anchored mechanics (SOPS/CMP, kustomize images, edge-smoke shape); MEDIUM for external action/library version pins (web-verified but pin-to-SHA at plan time); ASSUMED items are flagged in the Assumptions Log.

## Summary

This phase builds two things from scratch: a **Go scaffolder CLI** and the **CI/GitOps promotion loop** it wires up. The scaffolder runs in-place inside an app repo, generates a Dockerfile + a GitHub Actions workflow, and commits per-app Kubernetes manifests into `apps/<slug>/` of the private `tkayage/gitops-homelab` repo (the ApplicationSet source). Thereafter, a push to `main` triggers: build → push `ghcr.io/tkayage/<slug>:sha-<short>` (private) → CI checks out `gitops-homelab`, runs `kustomize edit set image` under `apps/<slug>/`, commits+pushes `main` → Argo auto-syncs the pinned SHA.

The single most important verified fact for planning: the existing `sops-kustomize-v1.0` CMP plugin **decrypts every `*.enc.yaml` to `*.yaml`, deletes the `.enc.yaml`, then runs `kustomize build`** (`infrastructure/kubernetes/argocd/cmp-plugin.yaml`). This means (a) the per-app `kustomization.yaml` must reference the **decrypted** filename (`pull-secret.yaml`, not `pull-secret.enc.yaml`) — confirmed by the live `gitops-smoke` example — and (b) because the CMP just runs stock `kustomize build`, a kustomization mixing `resources:` and an `images:` transformer works natively, so `kustomize edit set image` is the correct promotion mechanism with no plugin changes required.

**Primary recommendation:** Model each scaffolded app on `gitops/apps/edge-smoke/` (Deployment + Service + Ingress + `kustomization.yaml`) plus a `gitops/apps/gitops-smoke/`-style SOPS `*.enc.yaml` for the GHCR pull secret. Use three distinct credentials with least privilege: the built-in `GITHUB_TOKEN` (packages:write) for build→push, a fine-grained PAT (Contents:write on `gitops-homelab` only) for the cross-repo bump, and a dedicated **classic** read:packages token embedded in the SOPS pull secret for k8s pulls (fine-grained PATs are unreliable for GHCR reads). Build the scaffolder with `cobra` + `text/template` + `embed`, and shell out to the system `git` for the cross-repo commit rather than adopting go-git.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Scaffolder written in **Go** — single static binary, no runtime deps, cross-platform CLI.
- Runs **in-place** inside an existing app repo; adds a Dockerfile, a GitHub Actions workflow, and registers the app's GitOps manifests. New-project generation is deferred.
- Commits the app's manifests **directly to `apps/<slug>/` in `tkayage/gitops-homelab`** (the ApplicationSet source).
- **One canonical slug** drives everything: derive from repo/dir name, validate `^[a-z][a-z0-9-]{1,30}$`, `--slug` override. Slug → image `ghcr.io/tkayage/<slug>`, namespace `<slug>`, host `<slug>.app.kayage.co`, gitops dir `apps/<slug>`.
- **GitHub Actions**, triggered on **push to `main`** → build → push → bump gitops.
- Immutable primary tag = **short git SHA** (`ghcr.io/tkayage/<slug>:sha-<short>`) plus moving `latest`; GitOps pins the SHA tag.
- **Generate a proven multi-stage T3/Next standalone Dockerfile**; for non-T3 repos, **detect and validate an existing Dockerfile** rather than overwriting it (SCAF-06).
- CI **bumps the image ref by committing to gitops-homelab** — `kustomize edit set image ghcr.io/tkayage/<slug>=...:sha-<short>` in `apps/<slug>/`, commit + push `main`; Argo auto-syncs. No in-cluster image-updater controller.
- CI authenticates to the private gitops repo with a **fine-grained PAT or deploy key** stored as a GitHub Actions secret (final choice at planning).
- **Private GHCR** images. Each app carries a **per-app SOPS `pull-secret.enc.yaml`** (dockerconfigjson) decrypted by the existing `sops-kustomize-v1.0` CMP and referenced via `imagePullSecrets`.
- Per-app manifests mirror the `edge-smoke` exemplar: Deployment, Service, Ingress (`<slug>.app.kayage.co`, ingressClassName traefik), pull-secret.enc.yaml, and a kustomization.yaml with an `images:` block; namespace auto-created by the ApplicationSet (`CreateNamespace=true`).
- Health: readiness + liveness `httpGet /api/health` for T3 (scaffolder adds the route); TCP probe on the container port for non-T3, overridable.
- Defaults: 1 replica, container port 3000, bounded CPU/memory requests+limits, RollingUpdate.
- Scaffolder reports (SCAF-05): generated files, the gitops commit it pushed, the expected URL `https://<slug>.app.kayage.co`, and the Argo application name + how to check health.

### Claude's Discretion
- Go module layout and binary name, template-engine usage (`text/template` + `embed`), exact Dockerfile base-image pins and stages, GitHub Actions action versions, the final PAT-vs-deploy-key pick, and the T3 health-route implementation follow current best practices and existing repo conventions.

### Deferred Ideas (OUT OF SCOPE)
- New-project generation from a T3 template (`--new`) — scaffolder is in-place only for v1.
- Argo CD Image Updater and reflector-based shared pull secrets.
- Public exposure (Phase 7); the real end-to-end validation app (Phase 8).
- Staging environments / promotion and per-app Postgres/OIDC auto-provisioning (OPS-02, DX-01, DX-05).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GITOPS-03 | App repos build and publish versioned images to GHCR on push | GitHub Actions workflow §2: `docker/build-push-action` + `docker/metadata-action` for `sha-<short>` + `latest`; `GITHUB_TOKEN` packages:write; private-by-default GHCR |
| GITOPS-04 | CI updates the GitOps image reference and triggers deployment without manual cluster commands | Cross-repo bump §3: checkout `gitops-homelab` with fine-grained PAT, `kustomize edit set image`, commit+push `main`; Argo auto-sync (verified live in `gitops-platform.sh prove-rollback`) |
| SCAF-01 | Scaffold any containerizable project with one command | Go CLI §1 (cobra + embed + text/template); slug derivation §8 |
| SCAF-02 | Scaffolding generates or validates its Dockerfile and GitHub Actions workflow | T3 Dockerfile §4; non-T3 detect/validate §7; workflow templates §2/§3 |
| SCAF-03 | Scaffolding creates the app's GitOps config from one canonical slug | edge-smoke manifest shape §6; kustomization `images:` block; commit to `apps/<slug>/` |
| SCAF-04 | Generated workloads include health probes and private GHCR pull credentials | Probes (T3 httpGet `/api/health`, non-T3 TCP) §4/§7; SOPS dockerconfigjson §5 |
| SCAF-05 | Scaffolding reports created resources, deployment status, and expected URL | Reporting §9 (best-effort health, cluster access optional) |
| SCAF-06 | T3 works out of the box; non-T3 containers provide own image config | Dockerfile detection/validation §7 |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Scaffolding (file gen, cross-repo commit) | Dev workstation (Go CLI) | — | One-time operator step; runs in the app repo, not in-cluster |
| Image build + push | CI (GitHub Actions runner) | GHCR (registry) | Build belongs on the runner; artifact lands in the registry |
| Image ref promotion (bump) | CI (GitHub Actions runner) | `gitops-homelab` repo (git as SoT) | Git remains the single deployment source of truth |
| Reconciliation / deploy | API/Cluster (Argo CD + ApplicationSet) | k3s | Argo owns in-cluster objects; auto-sync on git change |
| Secret decryption | Cluster (Argo repo-server CMP) | age key (in-cluster secret) | SOPS decrypt happens at manifest-generation time inside Argo |
| Ingress / TLS | Edge (Traefik → NPM wildcard) | — | Established in Phase 4; app only declares an Ingress host |
| Private image pull | Cluster (kubelet + imagePullSecret) | GHCR | Per-app dockerconfigjson referenced by the Deployment |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `github.com/spf13/cobra` | v1.10.2 | CLI command/flag framework | De-facto Go CLI standard (kubectl, gh, hugo). Latest release 2025-12-04. [CITED: pkg.go.dev/github.com/spf13/cobra] |
| `text/template` + `embed` | stdlib (Go 1.26) | Bundle & render Dockerfile / YAML / workflow templates into the binary | Zero external deps, `//go:embed` gives a single static binary carrying all templates [VERIFIED: go1.26.4 present on dev box] |
| System `git` (via `os/exec`) | 2.x | Clone + commit + push to `gitops-homelab` | Reuses the credential/askpass pattern already proven in `scripts/gitops-platform.sh`; no new dependency surface [VERIFIED: gitops-platform.sh] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `github.com/spf13/pflag` | (transitive via cobra) | POSIX flags (`--slug`, `--port`, `--dockerfile`) | Comes with cobra; no separate install |
| `os/exec` → `sops` | binary v3.13.2 | Encrypt the generated `pull-secret.enc.yaml` | Encryption step during scaffolding (see §5, Environment gap: sops not on PATH) |
| `os/exec` → `kustomize` | v5.x | Validate generated kustomization locally; used by CI for the bump | Dev-box validation + CI bump (see §6, Environment gap: kustomize not on PATH) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| System `git` via `os/exec` | `github.com/go-git/go-git/v6` (pure-Go) | go-git avoids a git binary dependency, but adds a large dependency tree, is slower for push, and does not reuse the working askpass/token flow already in the repo. For a dev-box tool where git is always present, `os/exec` is simpler and matches repo conventions. Recommend `os/exec`. [CITED: pkg.go.dev/github.com/go-git/go-git/v6] |
| cobra | stdlib `flag` | stdlib is fine for a flat command set, but cobra gives subcommands (`scaffold`, future `remove`), `--help`, and completion for near-zero cost. Recommend cobra given deferred future commands. |
| `text/template` | `html/template` | `html/template` HTML-escapes output — wrong for YAML/Dockerfiles. Use `text/template`. |

**Installation (scaffolder module):**
```bash
# In the homelab repo, create an isolated Go module for the tool:
#   scaffold/go.mod  ->  module github.com/tkayage/homelab/scaffold
go get github.com/spf13/cobra@v1.10.2
```

**Distribution recommendation:** The homelab repo currently has **no configured git remote** (`git remote -v` is empty) and is private, so `go install github.com/tkayage/homelab/scaffold/cmd/...@latest` will not resolve for an operator. Recommend: commit source under `scaffold/`, run via `go run ./scaffold <args>` during development and provide a `Makefile`/`justfile` target that does `go build -o .local/bin/scaffold ./scaffold/cmd/scaffold`. **Do not commit the compiled binary** (binaries in git are an anti-pattern and bloat history). If a public module path is later desired, publish the module then switch to `go install`. Module path `github.com/tkayage/homelab/scaffold` is `[ASSUMED]` — confirm the intended remote before hardcoding it in `go.mod`.

**Version verification (run at plan/execute time):**
```bash
go list -m -versions github.com/spf13/cobra        # confirm v1.10.2 current
# GitHub Actions: pin to full commit SHA, not floating majors (supply-chain, see Security Domain)
```

## Package Legitimacy Audit

> The scaffolder is a Go module; the CI it emits pulls GitHub Actions. None are npm/PyPI/crates, so the `package-legitimacy` seam (npm/pypi/crates only) does not apply. Verified manually against official sources.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `github.com/spf13/cobra` | Go / pkg.go.dev | 9+ yrs | Ubiquitous (kubectl, gh, hugo) | github.com/spf13/cobra | OK | Approved [CITED: pkg.go.dev] |
| `github.com/go-git/go-git/v6` | Go / pkg.go.dev | 10+ yrs | Used by Gitea, Flux, Prow | github.com/go-git/go-git | OK | Not selected (alt only) |
| `docker/build-push-action` | GitHub Actions | official | Docker Inc. maintained | github.com/docker/build-push-action | OK | Approved — pin to SHA |
| `docker/login-action` | GitHub Actions | official | Docker Inc. maintained | github.com/docker/login-action | OK | Approved — pin to SHA |
| `docker/metadata-action` | GitHub Actions | official | Docker Inc. maintained | github.com/docker/metadata-action | OK | Approved — pin to SHA |
| `docker/setup-buildx-action` | GitHub Actions | official | Docker Inc. maintained | github.com/docker/setup-buildx-action | OK | Approved — pin to SHA |
| `actions/checkout` | GitHub Actions | official | GitHub maintained | github.com/actions/checkout | OK | Approved — pin to SHA |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 Operator (dev workstation)
      │  run once:  go run ./scaffold  (in app repo)
      ▼
 ┌──────────────── Go scaffolder (cobra + embed + text/template) ────────────────┐
 │ 1. derive/validate slug  2. detect T3 vs non-T3  3. render templates          │
 │                                                                                │
 │  writes into APP repo:            commits into gitops-homelab repo:            │
 │   ├─ Dockerfile (T3) / validate    apps/<slug>/                                │
 │   │   existing (non-T3)              ├─ deployment.yaml (imagePullSecrets)     │
 │   ├─ .github/workflows/deploy.yml    ├─ service.yaml                           │
 │   └─ app/api/health/route.ts (T3)    ├─ ingress.yaml (<slug>.app.kayage.co)    │
 │                                      ├─ pull-secret.enc.yaml (SOPS)            │
 │                                      └─ kustomization.yaml (resources+images) │
 │ 4. sops-encrypt pull secret   5. git commit+push gitops main   6. report      │
 └───────────────────────────────────┬──────────────────────────┬───────────────┘
                                      │ (push app main, later)    │ (initial commit)
                                      ▼                            ▼
   ┌─────────────── GitHub Actions (app repo, on push main) ──────┐   gitops-homelab@main
   │ build job:                                                   │        │
   │  login GHCR (GITHUB_TOKEN, packages:write)                   │        │
   │  metadata-action -> tags sha-<short> + latest                │        │
   │  build-push-action -> ghcr.io/tkayage/<slug> (PRIVATE)       │        │
   │ bump job (needs: build):                                     │        │
   │  checkout gitops-homelab (fine-grained PAT, Contents:write)  │        │
   │  kustomize edit set image .:sha-<short> in apps/<slug>       │        │
   │  git commit + push main  ───────────────────────────────────┼────────┘
   └──────────────────────────────────────────────────────────────┘        │
                                                                            ▼
                       Argo CD ApplicationSet (homelab-apps, git-dir apps/*)
                         └─ Application '<slug>' -> CMP sops-kustomize-v1.0
                              decrypt *.enc.yaml -> kustomize build -> apply
                              auto-sync (prune+selfHeal), CreateNamespace=true
                                                                            │
                                                                            ▼
                       k3s: ns <slug>  ┌ Deployment (pulls PRIVATE image via
                                       │   imagePullSecrets: ghcr-pull)
                                       ├ Service :80 -> :3000
                                       └ Ingress traefik -> <slug>.app.kayage.co
                                              │
                                              ▼  (Phase 4 edge)
                                   Traefik 10.10.30.102 -> NPM 10.10.30.237 (wildcard TLS)
                                              │
                                              ▼
                                   https://<slug>.app.kayage.co
```

### Component Responsibilities
| File / component | Responsibility |
|------------------|----------------|
| `scaffold/cmd/scaffold/main.go` | cobra root, flag parsing, orchestration |
| `scaffold/internal/slug` | derive from repo/dir basename, validate regex |
| `scaffold/internal/detect` | T3 detection (package.json → next dep) vs existing Dockerfile |
| `scaffold/internal/templates` (`//go:embed`) | Dockerfile, deploy.yml, k8s manifests, health route |
| `scaffold/internal/gitops` | clone/pull gitops-homelab, write `apps/<slug>/`, sops-encrypt, commit+push |
| `scaffold/internal/report` | SCAF-05 output |

### Recommended Project Structure
```
scaffold/
├── go.mod                       # module github.com/tkayage/homelab/scaffold (confirm remote)
├── cmd/scaffold/main.go         # cobra entrypoint
├── internal/
│   ├── slug/slug.go
│   ├── detect/detect.go
│   ├── gitops/gitops.go         # os/exec git + sops
│   └── report/report.go
└── templates/                   # //go:embed templates/*
    ├── Dockerfile.t3.tmpl
    ├── workflow.deploy.yml.tmpl
    ├── health.route.ts.tmpl
    └── gitops/
        ├── deployment.yaml.tmpl
        ├── service.yaml.tmpl
        ├── ingress.yaml.tmpl
        ├── kustomization.yaml.tmpl
        └── pull-secret.yaml.tmpl   # rendered, then sops-encrypted to *.enc.yaml
```

### Pattern 1: Two-job workflow with build→bump ordering
**What:** A single workflow file with a `build` job and a `bump` job declaring `needs: build`, so the gitops image reference is only advanced after the image is confirmed pushed.
**When to use:** Every scaffolded app.
**Example:** see Code Examples §2/§3.

### Pattern 2: SOPS filename indirection (CRITICAL)
**What:** On disk the secret is `pull-secret.enc.yaml`; the `kustomization.yaml` references `pull-secret.yaml`. The CMP decrypts and renames before `kustomize build` sees it.
**Why it matters:** Referencing `pull-secret.enc.yaml` in `resources:` makes `kustomize build` fail (file not found after rename). [VERIFIED: cmp-plugin.yaml + live gitops-smoke/kustomization.yaml references `secret.yaml` while file is `secret.enc.yaml`]

### Anti-Patterns to Avoid
- **In-cluster image updater (Argo Image Updater):** explicitly deferred; git stays SoT. Do not add it.
- **Overwriting an existing non-T3 Dockerfile:** SCAF-06 forbids it — detect + validate only.
- **Floating action tags (`@v6`) in generated workflows:** pin to full commit SHA for supply-chain integrity (see Security Domain).
- **Fine-grained PAT for the k8s GHCR pull secret:** unreliable for GHCR reads; use a classic read:packages token. [CITED: github.com/docker/login-action/issues/331]
- **Embedding the age private key or any token in the scaffolder binary or app repo:** the pull secret is SOPS-encrypted; the age key lives only in-cluster and at `~/.config/homelab/age/keys.txt`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image tag/label generation | Custom SHA-shortening + tag string logic | `docker/metadata-action` | Handles `sha-<short>`, `latest`, OCI labels, edge cases |
| GHCR login | Manual `docker login` with echoed token | `docker/login-action` | Masks token, cleans up creds post-job |
| Buildx build+push+cache | Raw `docker build`/`push` | `docker/build-push-action` | GHA cache, multi-arch, provenance |
| Kustomize image pin | `sed` on `newTag:` | `kustomize edit set image` | Deterministic, respects the `images:` schema |
| Secret encryption | Custom crypto | `sops` + age (existing) | Reuses Phase 3 pattern; never hand-roll crypto |
| CLI flag parsing / help | Hand-rolled arg loop | `cobra` | Subcommands, help, completion |

**Key insight:** Every moving part in this phase already has a blessed, in-repo or upstream-official implementation. The scaffolder's job is orchestration and templating, not reimplementing build/registry/crypto primitives.

## Runtime State Inventory

> This is a greenfield build phase (new CLI + new CI), not a rename/migration. Included for the cross-repo state it touches.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore keys renamed. | None |
| Live service config | Argo ApplicationSet `homelab-apps` auto-adopts any new `apps/<slug>/` dir (git-dir generator over `apps/*`). No Argo change needed per app. [VERIFIED: applicationset.yaml] | None — new dirs auto-register |
| OS-registered state | None. | None |
| Secrets/env vars | New: per-app GHCR pull token (classic read:packages) inside `pull-secret.enc.yaml`; new GitHub Actions secret `GITOPS_PUSH_TOKEN` (fine-grained PAT, Contents:write on gitops-homelab). Existing `github.env` (`GITHUB_TOKEN`) and age key reused by the operator's local flow. | Operator must create the two new tokens (checkpoint) |
| Build artifacts | Scaffolder binary built to `.local/bin/` (gitignored), not committed. | None |

## Common Pitfalls

### Pitfall 1: kustomization references the encrypted filename
**What goes wrong:** `resources: [pull-secret.enc.yaml]` → `kustomize build` fails after the CMP renames the file to `pull-secret.yaml`.
**Why it happens:** The CMP decrypts `*.enc.yaml`→`*.yaml` and `rm`s the `.enc.yaml` before building.
**How to avoid:** Reference the **decrypted** name in `resources:`. [VERIFIED: cmp-plugin.yaml + gitops-smoke]
**Warning signs:** Argo app `SyncFailed` / "accumulating resources ... no such file".

### Pitfall 2: Image name in Deployment doesn't match the `images:` transformer key
**What goes wrong:** `kustomize edit set image` writes an `images:` entry keyed on `ghcr.io/tkayage/<slug>`, but the Deployment `image:` uses a different string (e.g. includes a tag mismatch), so the transformer no-ops.
**How to avoid:** Deployment `image: ghcr.io/tkayage/<slug>` (name only, or with `:latest`); `images:` entry `name: ghcr.io/tkayage/<slug>` + `newTag: sha-<short>`. Keep the `name` byte-identical.
**Warning signs:** Pod runs `:latest` instead of the pinned SHA after a bump.

### Pitfall 3: GHCR package private but pull secret missing/wrong
**What goes wrong:** `ErrImagePull` / `ImagePullBackOff` because the private package needs `imagePullSecrets` and the token lacks read:packages, or a fine-grained PAT is used.
**How to avoid:** Classic PAT with read:packages in the dockerconfigjson; Deployment sets `imagePullSecrets: [{name: ghcr-pull}]`. [CITED: docker/login-action#331]
**Warning signs:** `unauthorized` in pod events.

### Pitfall 4: Bump runs before build finishes (race)
**What goes wrong:** Argo tries to pull a SHA tag that isn't pushed yet.
**How to avoid:** `bump` job `needs: build`; compute the short SHA once and pass it via job output, not re-derive.
**Warning signs:** Transient `ImagePullBackOff` that self-heals on retry.

### Pitfall 5: `github.sha` is the merge/head SHA, and "short" length varies
**What goes wrong:** Ambiguous or mismatched short SHA between the image tag and the gitops pin.
**How to avoid:** Derive the short SHA once (`echo "${GITHUB_SHA::7}"` or `metadata-action`'s `type=sha,format=short`) and reuse the exact string in both the push tag and `kustomize edit set image`.

### Pitfall 6: Two-writer contention on gitops-homelab main
**What goes wrong:** Multiple app CI runs push to `main` concurrently → non-fast-forward rejects.
**How to avoid:** In the bump job, `git pull --rebase` (or fetch+reset to origin/main, re-apply the single edit) with a small retry loop before push. Each app only edits its own `apps/<slug>/` so conflicts are rare but pushes can still race.

## Code Examples

### 1. T3 / Next.js standalone Dockerfile (generated)
```dockerfile
# Source: Next.js self-hosting docs pattern (output: 'standalone'); pin digests at plan time.
# syntax=docker/dockerfile:1
ARG NODE_VERSION=22.17.0

FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# Requires next.config: `output: 'standalone'` (scaffolder should assert/inject this)
RUN npm run build

FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```
Notes: `HOSTNAME=0.0.0.0` is required or Next binds to localhost and probes fail. The scaffolder must ensure `next.config.{js,ts}` has `output: 'standalone'`. [CITED: nextjs.org self-hosting / Docker standalone guides]

### 2. Health route (T3, App Router — generated)
```ts
// app/api/health/route.ts  — Source: Next.js App Router route handler
export const dynamic = 'force-dynamic';
export function GET() {
  return new Response('ok', { status: 200 });
}
```

### 3. GitHub Actions workflow (generated) — build → push → bump
```yaml
# .github/workflows/deploy.yml  — pin action refs to full commit SHA at plan time.
name: deploy
on:
  push:
    branches: [main]
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false
permissions:
  contents: read
  packages: write
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      short_sha: ${{ steps.vars.outputs.short_sha }}
    steps:
      - uses: actions/checkout@v4                       # pin to SHA
      - id: vars
        run: echo "short_sha=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
      - uses: docker/setup-buildx-action@v3             # v4 available; pin SHA
      - uses: docker/login-action@v3                    # v4 available; pin SHA
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5                 # pin SHA
        with:
          images: ghcr.io/tkayage/<slug>
          tags: |
            type=sha,prefix=sha-,format=short
            type=raw,value=latest,enable={{is_default_branch}}
      - uses: docker/build-push-action@v6               # v7 available; pin SHA
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  bump:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4                       # pin SHA
        with:
          repository: tkayage/gitops-homelab
          token: ${{ secrets.GITOPS_PUSH_TOKEN }}       # fine-grained PAT, Contents:write
          ref: main
      - name: install kustomize
        run: |
          curl -sfL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash -s 5.4.3 /usr/local/bin
      - name: pin image
        working-directory: apps/<slug>
        run: |
          kustomize edit set image ghcr.io/tkayage/<slug>=ghcr.io/tkayage/<slug>:sha-${{ needs.build.outputs.short_sha }}
      - name: commit + push
        run: |
          git config user.name  "homelab-ci"
          git config user.email "ci@homelab.invalid"
          git add apps/<slug>/kustomization.yaml
          git commit -m "deploy(<slug>): sha-${{ needs.build.outputs.short_sha }}" || exit 0
          for i in 1 2 3; do
            git pull --rebase origin main && git push origin main && break
            sleep $((RANDOM % 5 + 2))
          done
```
Version note: web-verified current majors are build-push-action **v7**, setup-buildx **v4**, login **v4**, metadata **v5** [CITED: github.com/docker/*]. The example shows widely-deployed majors; the planner should pin each to a full commit SHA of the chosen version.

### 4. Per-app kustomization.yaml (gitops-homelab, generated)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - pull-secret.yaml        # decrypted name; on-disk file is pull-secret.enc.yaml
images:
  - name: ghcr.io/tkayage/<slug>
    newTag: latest           # CI rewrites via `kustomize edit set image`
```

### 5. SOPS dockerconfigjson pull secret (pre-encryption shape)
```yaml
# pull-secret.yaml (rendered) -> sops -e -> pull-secret.enc.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-pull
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {"auths":{"ghcr.io":{"username":"tkayage","password":"<CLASSIC_PAT_read:packages>","auth":"<base64(tkayage:PAT)>"}}}
```
`encrypted_regex: ^(data|stringData)$` encrypts the whole `stringData` block, matching the `.sops.yaml` rule and the live `gitops-smoke/secret.enc.yaml` shape. [VERIFIED: .sops.yaml + gitops-smoke/secret.enc.yaml]
Encrypt with:
```bash
SOPS_AGE_KEY_FILE=~/.config/homelab/age/keys.txt \
  sops --encrypt --in-place pull-secret.enc.yaml   # or -e file.yaml > file.enc.yaml
```

### 6. Deployment snippet (T3, generated) — probes + pull secret
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: ghcr-pull
      containers:
        - name: app
          image: ghcr.io/tkayage/<slug>        # matches images: name; tag set by transformer
          ports: [{ name: http, containerPort: 3000 }]
          readinessProbe: { httpGet: { path: /api/health, port: http }, periodSeconds: 5 }
          livenessProbe:  { httpGet: { path: /api/health, port: http }, periodSeconds: 10 }
          resources:
            requests: { cpu: 25m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 512Mi }
  strategy: { type: RollingUpdate }
```
Non-T3 variant replaces the probes with `tcpSocket: { port: <detected> }`.

### 7. Slug derivation + validation (Go, generated logic)
```go
var slugRe = regexp.MustCompile(`^[a-z][a-z0-9-]{1,30}$`)

func deriveSlug(dir string) (string, error) {
    base := strings.ToLower(filepath.Base(dir))
    base = regexp.MustCompile(`[^a-z0-9-]`).ReplaceAllString(base, "-")
    base = strings.Trim(base, "-")
    if !slugRe.MatchString(base) {
        return "", fmt.Errorf("cannot derive valid slug from %q; pass --slug", dir)
    }
    return base, nil
}
// repo discovery: `git rev-parse --show-toplevel` (is it a repo?) and
// `git remote get-url origin` (which repo CI runs in; validate, do not fail if absent).
// image name is ALWAYS ghcr.io/tkayage/<slug> (slug-canonical, independent of remote).
```

### 8. Non-T3 Dockerfile validation (SCAF-06)
```
detect: package.json present AND "next" in deps  -> T3 path (generate Dockerfile + health route)
        else                                     -> non-T3 path
non-T3 validation (warn, don't overwrite):
  - Dockerfile exists at repo root (or --dockerfile path)
  - has an EXPOSE line -> derive container port (fallback --port, default 3000)
  - has a `USER` line that is not root -> warn if missing (non-root recommendation)
  - probe = tcpSocket on the resolved port (overridable via flag)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `next build` copies full `node_modules` into image | `output: 'standalone'` self-contained server | Next.js 12+ | ~70% smaller images; needs `HOSTNAME=0.0.0.0` |
| Argo CD Image Updater / kubectl set image | CI writes git (`kustomize edit set image`) | current homelab decision | Git is SoT; deterministic; no in-cluster controller |
| Classic PAT for everything | Least-privilege split (GITHUB_TOKEN / fine-grained PAT / classic read:packages) | current | Smaller blast radius; note FG-PAT still unreliable for GHCR reads |
| Floating action tags `@v6` | Pin to full commit SHA | supply-chain norm | Prevents tag-move attacks |

**Deprecated/outdated:**
- go-git v5 / go-billy v5 are in maintenance; v6 is current — but we recommend `os/exec` git regardless. [CITED: pkg.go.dev]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Go module path `github.com/tkayage/homelab/scaffold` | Standard Stack / Distribution | `go.mod` path wrong; must edit before publishing/`go install`. Repo has NO remote configured — confirm intended remote. |
| A2 | GHCR org/user is `tkayage` and images are `ghcr.io/tkayage/<slug>` | throughout | Wrong registry path breaks build+pull. (Strongly implied by CONTEXT + gitops repo `tkayage/gitops-homelab`, but not directly verified from a git remote.) |
| A3 | A fine-grained PAT with Contents:write works for the cross-repo git push | §3 | If org policy blocks FG-PATs on the repo, fall back to a deploy key (SSH). FG-PATs DO work for git Contents (the GHCR limitation is registry-only). |
| A4 | Latest action majors (build-push v7, buildx v4, login v4, metadata v5) | §Code Examples | Cosmetic; planner pins exact SHA. |
| A5 | T3 apps use App Router (`app/api/health/route.ts`) | §Code Examples | Pages Router apps need `pages/api/health.ts` instead — scaffolder should detect router type or offer a flag. |
| A6 | cobra v1.10.2 is current | Standard Stack | Cosmetic; `go get @latest` at build. |
| A7 | Dev box needs `sops` + `kustomize` installed for local scaffolding/validation | Environment | Blocks local encrypt/validate until installed (both are absent from PATH). |

## Open Questions

1. **PAT vs deploy key for the gitops bump (final pick).**
   - What we know: FG-PAT Contents:write is simplest for a solo operator (one token reusable across app repos as a shared Actions secret); a deploy key is per-repo-pair but strictly scoped.
   - Recommendation: **fine-grained PAT `GITOPS_PUSH_TOKEN`** scoped to `gitops-homelab` only, Contents:write. Fall back to deploy key only if org policy forbids FG-PATs.

2. **Whom does the GHCR pull token authenticate as?**
   - What we know: classic PAT read:packages works; ideally a dedicated machine account, but a solo homelab can use the operator's classic PAT.
   - Recommendation: dedicated classic PAT with only read:packages; rotate via re-encrypting `pull-secret.enc.yaml`.

3. **Does the scaffolder shell out to `sops`, or require pre-installed?**
   - Recommendation: shell out to `sops` (reuse `~/.config/homelab/age/keys.txt`); fail with a clear message if `sops` is absent. Consider using the already-downloaded `.local/downloads/sops-v3.13.2.linux.amd64`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Go toolchain | Building the scaffolder | ✓ | go1.26.4 | — |
| Docker | Local Dockerfile build test (GITOPS-03) | ✓ | 29.4.0 | — |
| kubectl + cluster | SCAF-04/05 live verification | ✓ | via `KUBECONFIG=.local/kubeconfig-k3s-01` (8 namespaces incl. argocd) | — |
| `sops` | Encrypt `pull-secret.enc.yaml` | ✗ (not on PATH) | — | Pinned binary at `.local/downloads/sops-v3.13.2.linux.amd64`; install to PATH |
| `kustomize` | Local kustomization validation; CI bump | ✗ (not on PATH) | — | `kubectl kustomize` builds but lacks `edit set image`; install kustomize v5.x |
| `gh` CLI | Optional (token/package admin) | ✗ | — | Use REST API / git directly (as `gitops-platform.sh` does) |
| GitHub Actions runners | Real build→push→bump (GITOPS-03/04) | n/a (cloud) | — | Requires a real app repo on GitHub with Actions — Phase 8 provides it; use a fixture for Phase 6 |
| age key | SOPS decrypt/encrypt | ✓ | `~/.config/homelab/age/keys.txt` (mode 600) | — |
| GitHub creds | gitops push | ✓ | `~/.config/homelab/github.env` (`GITHUB_TOKEN`) | — |

**Missing dependencies with no fallback:**
- A **real GitHub app repo with Actions enabled** is required to exercise the full push→build→bump→deploy loop end-to-end. Phase 6 can validate every component in isolation on the dev box, but the true E2E belongs to Phase 8. Recommend a minimal throwaway fixture repo (a tiny containerized app) to prove the pipeline within Phase 6.

**Missing dependencies with fallback:**
- `sops`, `kustomize` — install from pinned sources (both already have a pinned reference in the repo's download flow).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Go `testing` (stdlib) for the scaffolder; shell/bats-style scripts + `kubectl` assertions for pipeline/GitOps |
| Config file | none yet — `scaffold/go.mod` + `go test ./...` (Wave 0 creates) |
| Quick run command | `go test ./scaffold/...` |
| Full suite command | `go test ./scaffold/... && scripts/scaffold-verify.sh` (new helper) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCAF-01 | one command scaffolds a temp app repo | integration (Go, tmp git repo) | `go test ./scaffold/internal/gitops -run TestScaffoldEndToEnd` | ❌ Wave 0 |
| SCAF-02 | generates T3 Dockerfile + workflow; validates non-T3 | golden-file (Go) | `go test ./scaffold/internal/templates -run TestGolden` | ❌ Wave 0 |
| SCAF-03 | writes `apps/<slug>/` manifests from slug | unit + golden | `go test ./scaffold/internal/gitops -run TestManifestSet` | ❌ Wave 0 |
| SCAF-04 | probes present; SOPS pull-secret decrypts + pod pulls | integration + live | `go test ...TestProbes` then `kubectl -n <slug> get deploy,secret,pod` (no ImagePullBackOff) | ❌ Wave 0 |
| SCAF-05 | reports files, gitops commit, URL, argo app | unit (capture stdout) | `go test ./scaffold/internal/report -run TestReport` | ❌ Wave 0 |
| SCAF-06 | detects/validates existing Dockerfile, TCP probe | unit (fixtures) | `go test ./scaffold/internal/detect -run TestNonT3` | ❌ Wave 0 |
| GITOPS-03 | build+push image to GHCR on push | live (fixture repo) | trigger workflow; assert `docker manifest inspect ghcr.io/tkayage/<slug>:sha-<short>` succeeds | ❌ Wave 0 (needs fixture repo) |
| GITOPS-04 | CI bumps gitops ref; Argo deploys | live | assert bump commit in gitops-homelab `apps/<slug>/kustomization.yaml`; `kubectl -n <slug> get deploy -o jsonpath image` == pinned SHA | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `go test ./scaffold/...`
- **Per wave merge:** full Go suite + `scripts/scaffold-verify.sh` (scaffold a fixture into a scratch gitops dir, `kustomize build`, dry-run apply)
- **Phase gate:** fixture app deployed live (`kubectl -n <slug>` Healthy, `curl -k https://<slug>.app.kayage.co` if edge reachable) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `scaffold/go.mod` + module skeleton — framework bootstrap
- [ ] `scaffold/internal/templates/*_test.go` — golden files covering SCAF-02/03
- [ ] `scaffold/internal/detect/*_test.go` — SCAF-06 fixtures (T3 + non-T3 with/without Dockerfile)
- [ ] `scaffold/internal/gitops/*_test.go` — temp-repo integration (SCAF-01/03)
- [ ] `scripts/scaffold-verify.sh` — offline `kustomize build` + SOPS round-trip check
- [ ] A minimal **fixture app repo** on GitHub (or a documented manual smoke) to exercise GITOPS-03/04 without waiting for Phase 8
- [ ] Install `sops` + `kustomize` on the dev box (Environment gaps)

## Security Domain

### Applicable ASVS Categories (Level 1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture / Secrets mgmt | yes | Tokens split by least privilege; secrets never in git plaintext (SOPS+age) |
| V5 Input Validation | yes | Slug regex `^[a-z][a-z0-9-]{1,30}$`; validate `--dockerfile`/`--port` |
| V6 Cryptography | yes | SOPS + age — reuse existing pattern; never hand-roll crypto |
| V10 Malicious Code / Supply Chain | yes | Pin GitHub Actions to full commit SHA; pin base image (digest), verify Go module provenance |
| V14 Configuration | yes | `permissions:` minimized (`contents: read`, `packages: write`); GHCR packages private by default |

### Known Threat Patterns for {Go CLI + GHA CI + GitOps}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Overprivileged / leaked cross-repo PAT | Elevation of Privilege | Fine-grained PAT scoped to `gitops-homelab` Contents:write only; or deploy key |
| Token exposure in logs | Information Disclosure | `docker/login-action` masks creds; never `echo` tokens; classic pull PAT lives only in SOPS ciphertext |
| Compromised action tag (tag-move) | Tampering | Pin `docker/*`, `actions/checkout` to full commit SHA |
| Malicious/rug-pulled base image | Tampering | Pin `node:<ver>-alpine` by digest; consider provenance/SBOM from build-push-action |
| Public GHCR package leak | Information Disclosure | Confirm package visibility = private (default on first push; verify in package settings) |
| Secret committed in plaintext | Information Disclosure | `.sops.yaml` `encrypted_regex ^(data|stringData)$`; scaffolder must encrypt before commit and refuse to push a plaintext secret |
| Slug injection into paths/manifests | Tampering | Strict regex validation; reject before any file write |

## Sources

### Primary (HIGH confidence — codebase, verified this session)
- `gitops/apps/edge-smoke/*` — Deployment/Service/Ingress/kustomization exemplar shape
- `gitops/apps/gitops-smoke/{kustomization.yaml,secret.enc.yaml}` — SOPS filename indirection (kustomization refs `secret.yaml`, file is `secret.enc.yaml`)
- `gitops/platform/applicationset.yaml` — git-dir generator over `apps/*`, CMP `sops-kustomize-v1.0`, auto-namespace, auto-sync
- `infrastructure/kubernetes/argocd/cmp-plugin.yaml` — CMP decrypts `*.enc.yaml`→`*.yaml`, then `kustomize build`
- `gitops/.sops.yaml` — age recipient + `encrypted_regex ^(data|stringData)$`
- `scripts/gitops-platform.sh` — proven gitops push flow, GITHUB_TOKEN askpass, `prove-rollback` (Argo auto-sync on git change)
- Live cluster: `kubectl get ns` (argocd, edge-smoke, gitops-smoke, shared-services active); Go 1.26.4, Docker 29.4.0 present

### Secondary (MEDIUM confidence — web-verified this session)
- pkg.go.dev / github.com/spf13/cobra — v1.10.2 (2025-12-04)
- pkg.go.dev / github.com/go-git/go-git v6 (alt, not selected)
- github.com/docker/{build-push,login,metadata,setup-buildx}-action — current majors v7/v4/v5/v4
- Next.js standalone Docker guides — `output: 'standalone'`, `HOSTNAME=0.0.0.0`, non-root uid 1001, three-stage build
- GitHub docs / docker/login-action#331 — GHCR package private-by-default; fine-grained PAT unreliable for GHCR reads

### Tertiary (LOW confidence — training knowledge, flagged in Assumptions Log)
- Go module path / GHCR org derivation (no git remote to verify)
- App Router vs Pages Router health-route location

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM — libraries web-verified, versions to be re-pinned at build; module path unverified (no remote)
- Architecture / GitOps mechanics: HIGH — CMP behavior, SOPS indirection, ApplicationSet, and Argo auto-sync all verified against live repo + cluster
- Pitfalls: HIGH — the highest-risk items (SOPS filename, image name match, pull secret) are codebase-verified
- CI details: MEDIUM — canonical GHA pattern; exact action versions/SHAs pinned by planner

**Research date:** 2026-07-08
**Valid until:** 2026-08-07 (30 days; re-pin action/library versions if later)
