# Stack Research: v1.1 Scaffolder CLI Service

**Project:** Homelab Deploy Platform
**Scope:** Stack additions/changes only for the Go scaffolder CLI milestone
**Researched:** 2026-07-12
**Overall confidence:** MEDIUM

## Recommendation

Keep the scaffolder as a small Go/Cobra CLI that shells out to the existing `git` and `sops` binaries. Add one Kubernetes-aware YAML editing library (`sigs.k8s.io/kustomize/kyaml`) for safe updates to existing GitOps manifests, and optionally add `golang.org/x/term` only if the missing-Dockerfile "offer" becomes an interactive TTY prompt. Do not add a Docker daemon client, live Kubernetes client, Helm SDK, GitHub SDK, secret manager, or new service.

The v1.1 work is file-oriented: inspect an app repository, generate or validate a Dockerfile, edit files in the GitOps repository, encrypt Secret YAML, commit, and push. The current stack already has most of what is needed.

## Current Stack To Keep

| Technology | Current / Target Version | Purpose | Why It Stays |
|------------|--------------------------|---------|--------------|
| Go module under `scaffold/` | repo currently declares `go 1.26.4` | CLI implementation | Existing scaffolder is already Go and has tests around detection, templates, GitOps publish, and SOPS guards. No rewrite. |
| `github.com/spf13/cobra` | v1.10.2 | CLI command/flag framework | Current latest from `go list`; official Cobra docs cover nested subcommands, POSIX flags, help, suggestions, and shell completions. Keep and add commands around the existing root behavior. |
| System `git` binary | existing shell-out | GitOps clone, add, commit, push | Current code already implements askpass/token handling and push preflight. Shelling out preserves normal Git behavior and avoids go-git edge cases. |
| System `sops` binary + age | SOPS v3.13.2 current release | Encrypt GitOps Secret manifests | Existing code already shells out with `--age`, `--encrypted-regex`, YAML input/output, and plaintext staging guards. SOPS Go package does not promise stable APIs except decrypt helpers, so do not import SOPS internals. |
| Standard library `text/template` / embedded templates | existing | Dockerfile and manifest generation | Sufficient for generated files. No template engine is needed. |
| GHCR, Argo CD, k3s, SOPS GitOps flow | already validated | Runtime deployment platform | Out of scope for this stack delta; v1.1 should only update files consumed by the existing pipeline. |

## Additions

| Add | Version | Purpose | Integration Point |
|-----|---------|---------|-------------------|
| `sigs.k8s.io/kustomize/kyaml` | v0.21.1 | Structured Kubernetes YAML updates while preserving resource shape and comments | Use in a new GitOps update package to load/edit `apps/<slug>/deployment.yaml`, `kustomization.yaml`, `configmap.yaml`, and secret references without wholesale rewrites. |
| `golang.org/x/term` | v0.45.0, optional | Detect interactive terminal and read confirmation input | Use only if `scaffold` prompts "Dockerfile missing; generate one?" in interactive mode. For CI/non-TTY, require explicit flags such as `--generate-dockerfile` or `--no-generate-dockerfile`. |

Recommended install command once implementation needs both:

```bash
cd scaffold
go get sigs.k8s.io/kustomize/kyaml@v0.21.1
go get golang.org/x/term@v0.45.0
```

If the CLI avoids interactive prompts and uses only explicit flags, skip `golang.org/x/term`.

## Feature-Specific Stack Decisions

### CLI Binary Mode

Use the existing Cobra root, but split behavior into explicit subcommands:

| Command | Responsibility |
|---------|----------------|
| `scaffold init` | Current new-service registration flow. Keep root command as a compatibility alias if desired. |
| `scaffold update` | Update an existing GitOps-managed service. |
| `scaffold env set` | Add/update non-secret environment variables. |
| `scaffold secret set` | Add/update encrypted GitOps Secret values. |
| `scaffold completion` | Generate shell completion via Cobra if useful on the dev server. |

Install on the dev server with Go's normal command install flow:

```bash
cd /home/tonny/homelab/scaffold
go install ./cmd/scaffold
```

Once this repo has tagged releases, prefer a pinned install:

```bash
go install github.com/tkayage/homelab/scaffold/cmd/scaffold@v1.1.0
```

Do not add Homebrew, Debian packaging, Goreleaser, or a daemon/service for v1.1. A local dev-server binary in `$GOBIN` is enough.

### Dockerfile-First Detection And Generation

Replace T3-first detection with:

1. Look for `--dockerfile` or `<project>/Dockerfile`.
2. If present, parse only what the scaffolder needs: first usable `EXPOSE`, presence of non-root `USER`, and basic Dockerfile existence.
3. If missing, offer generation from templates.
4. Use `--port` as the authoritative override because Docker `EXPOSE` is documentation, not a published port.

No Docker SDK, Docker daemon API, BuildKit library, or Hadolint dependency is needed. The official Dockerfile reference makes `EXPOSE` useful as a hint, but the scaffolder should not need to build the image locally.

For generated Dockerfiles, keep templates in the existing embedded template system. Use conservative generic templates:

| App Signal | Generated Dockerfile |
|------------|----------------------|
| `package.json` with Next.js | Existing Next/T3-style multi-stage template, renamed away from T3-specific assumptions. |
| `package.json` without Next.js | Node multi-stage template only if package scripts are clear enough; otherwise require user confirmation. |
| Unknown stack | Refuse automatic generation unless the user provides an explicit `--template` value. |

### Updating Existing GitOps Services

Add a small GitOps manifest editing layer using kyaml:

| File | Update Behavior |
|------|-----------------|
| `apps/<slug>/deployment.yaml` | Add/update container `env`, `envFrom`, image, port, and secret/config references. Preserve unrelated fields. |
| `apps/<slug>/configmap.yaml` | Store non-secret env values under `data`. Create if missing. |
| `apps/<slug>/secret.enc.yaml` | Store encrypted app secrets as a Kubernetes `Opaque` Secret. Create/update through SOPS. |
| `apps/<slug>/kustomization.yaml` | Ensure new ConfigMap/Secret resources are listed. Preserve existing resources. |

Do not add `client-go`: this CLI edits GitOps files offline and commits them. It should not talk to the live cluster API.

### Non-Secret Env Vars

Represent non-secret env vars as a ConfigMap plus Deployment reference:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-env
data:
  NODE_ENV: production
```

Then reference it from the container using `envFrom.configMapRef` unless the existing manifest already uses explicit `env` entries. This keeps bulk updates simple while allowing the CLI to preserve the local manifest style.

### Encrypted GitOps Secrets

Use Kubernetes `Secret` with `type: Opaque` and `stringData` as the plaintext working form, then encrypt before commit:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
stringData:
  DATABASE_URL: ...
```

Recommended implementation:

1. Decrypt existing `secret.enc.yaml` to a mode-0600 temp file outside the Git worktree, or create a temp plaintext Secret if missing.
2. Merge key updates using kyaml or a typed struct.
3. Re-encrypt to `secret.enc.yaml` with the same SOPS age recipient and `encrypted_regex: ^(data|stringData)$`.
4. Assert plaintext files are absent from `apps/<slug>/` before `git add`.
5. Stage only `apps/<slug>/`.

Keep using the SOPS CLI instead of importing `github.com/getsops/sops/v3` internals. The package documentation explicitly discourages direct use for stable APIs, while the CLI behavior is the stable operator contract.

## What Not To Add

| Avoid | Why |
|-------|-----|
| Docker SDK / BuildKit API | The CLI detects and generates files; it does not need to build images locally. CI already builds. |
| `client-go` / Kubernetes API client | Updates must flow through GitOps, not imperative cluster writes. |
| Helm SDK | Existing generated manifests are plain YAML/Kustomize-style app directories; adding Helm is a bigger platform change. |
| go-git | Current system-git implementation matches operator workflow and credential handling. |
| SOPS Go internals | API stability is not guaranteed for most packages; shelling out is safer. |
| Bubble Tea, Survey, PromptUI | Nice UX, unnecessary dependency surface. Use Cobra flags and optional simple TTY confirmation. |
| External Secrets Operator, Vault, Infisical | No new secret backend is required; SOPS+age is already validated. |
| New GitHub API client | Existing preflight uses `net/http`; normal commits use `git push`. |
| New daemon or web service | v1.1 target is a dev-server CLI binary, not a long-running service. |

## Implications For Roadmap

1. **CLI shape first:** Refactor commands and installation path before changing behavior. This protects the current one-shot scaffolding flow.
2. **Dockerfile detection/generation second:** Replace T3-first detection with Dockerfile-first detection while keeping generation explicit and reversible.
3. **GitOps update engine third:** Add kyaml-backed read/modify/write operations and tests against existing app directories.
4. **Env/secrets last:** Non-secret ConfigMap updates are simpler; encrypted Secret updates should come after the no-plaintext temp-file workflow is tested.

Testing should focus on golden GitOps directories, idempotent updates, plaintext-secret refusal, and "no-op means no commit" behavior.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Keep Go/Cobra | HIGH | Existing code uses Cobra; v1.10.2 is current from `go list`; official docs match needed command model. |
| Add kyaml | MEDIUM | kyaml is purpose-built for Kubernetes YAML editing; exact API ergonomics should be spiked before broad use. |
| Keep SOPS CLI | HIGH | Current implementation works; official Go package docs warn against direct unstable API use. |
| Avoid Docker/Kubernetes live clients | HIGH | Project requirement is GitOps commits, not imperative builds or cluster mutations. |
| Interactive prompt stack | MEDIUM | `x/term` is appropriate if prompting is required, but explicit flags may avoid the dependency entirely. |

## Sources

- [Cobra GitHub README](https://github.com/spf13/cobra) and [Cobra package docs](https://pkg.go.dev/github.com/spf13/cobra) - CLI features; `go list` verified `github.com/spf13/cobra v1.10.2`.
- [Go command docs](https://pkg.go.dev/cmd/go) and [Go install docs](https://go.dev/doc/install) - `go install` behavior and `$HOME/go/bin`.
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/) and [Dockerfile overview](https://docs.docker.com/build/concepts/dockerfile/) - `EXPOSE` semantics and `# syntax` directive.
- [Kubernetes env var task](https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/), [ConfigMap envFrom docs](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), and [Secret docs](https://kubernetes.io/docs/concepts/configuration/secret/) - `env`, `envFrom`, `stringData`, and `Opaque` Secret behavior.
- [SOPS reference docs](https://getsops.io/docs/reference/), [SOPS GitHub README](https://github.com/getsops/sops), and [SOPS Go package docs](https://pkg.go.dev/github.com/getsops/sops/v3) - YAML encryption model, age support, `encrypted_regex`, current v3.13.2 release, and API stability warning.
- [kyaml package docs](https://pkg.go.dev/sigs.k8s.io/kustomize/kyaml) - Kubernetes YAML resource editing; `go list` verified `sigs.k8s.io/kustomize/kyaml v0.21.1`.
- [x/term package docs](https://pkg.go.dev/golang.org/x/term) - TTY detection and terminal input; `go list` verified `golang.org/x/term v0.45.0`.

