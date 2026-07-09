# Phase 6: Build Pipeline and Project Scaffolding - Pattern Map

**Mapped:** 2026-07-08
**Files analyzed:** 18 (5 gitops-manifest templates, 3 app-repo templates, 6 Go source files, 1 workflow template, 1 verify script, 2 test bundles)
**Analogs found:** 11 with in-repo analog / 18 total (7 net-new with external-pattern-only reference)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scaffold/templates/gitops/deployment.yaml.tmpl` | config (k8s manifest) | request-response | `gitops/apps/edge-smoke/deployment.yaml` | exact (shape) |
| `scaffold/templates/gitops/service.yaml.tmpl` | config (k8s manifest) | request-response | `gitops/apps/edge-smoke/service.yaml` | exact |
| `scaffold/templates/gitops/ingress.yaml.tmpl` | config (k8s manifest) | request-response | `gitops/apps/edge-smoke/ingress.yaml` | exact |
| `scaffold/templates/gitops/kustomization.yaml.tmpl` | config (kustomize) | transform | `gitops/apps/gitops-smoke/kustomization.yaml` | role-match (SOPS indirection) + `edge-smoke/kustomization.yaml` |
| `scaffold/templates/gitops/pull-secret.yaml.tmpl` | config (k8s secret) | file-I/O (SOPS) | `gitops/apps/gitops-smoke/secret.enc.yaml` + `gitops/.sops.yaml` | role-match |
| `scaffold/templates/Dockerfile.t3.tmpl` | config (build) | batch | — (no Dockerfile in repo except `Dockerfile.sops`) | no analog (external: RESEARCH §1) |
| `scaffold/templates/workflow.deploy.yml.tmpl` | config (CI) | event-driven | — (no `.github/workflows` in repo) | no analog (external: RESEARCH §3) |
| `scaffold/templates/health.route.ts.tmpl` | route | request-response | — | no analog (external: RESEARCH §2) |
| `scaffold/cmd/scaffold/main.go` | controller (CLI entrypoint) | request-response | `scripts/gitops-platform.sh` (dispatch `case` block) | partial (bash→Go CLI conventions) |
| `scaffold/internal/slug/slug.go` | utility | transform | — | no analog (external: RESEARCH §7) |
| `scaffold/internal/detect/detect.go` | utility | transform | — | no analog (external: RESEARCH §8) |
| `scaffold/internal/gitops/gitops.go` | service | file-I/O + event-driven (git push) | `scripts/gitops-platform.sh` (`sync_worktree`/`publish`/`load_credentials`) | role-match |
| `scaffold/internal/report/report.go` | utility | request-response | `scripts/gitops-platform.sh` (`status`, `printf` reporting) | partial |
| `scaffold/go.mod` | config | — | — | no analog (net-new Go module) |
| `scripts/scaffold-verify.sh` | test (shell) | batch | `scripts/gitops-platform.sh` (bash header + `die`/`need` + dispatch) | role-match |
| `scaffold/internal/*/*_test.go` (golden/unit) | test | transform | — | no analog (net-new Go tests) |

## Pattern Assignments

### `scaffold/templates/gitops/deployment.yaml.tmpl` (config, request-response)

**Analog:** `gitops/apps/edge-smoke/deployment.yaml` (full file, 44 lines)

The edge-smoke deployment is the canonical shape: `app.kubernetes.io/name` label on metadata + selector + template, `replicas: 1`, a named `http` container port, an `httpGet` readiness probe on `port: http`, and bounded `resources.requests`/`limits`. Copy this skeleton; the template diverges as follows (per CONTEXT/RESEARCH §6):

- Replace `image: node:22.17.0-alpine` + `command`/`configMap` volume mount with `image: ghcr.io/tkayage/{{.Slug}}` (name-only, tag owned by the kustomize `images:` transformer — Pitfall 2) and no volume.
- Add `spec.template.spec.imagePullSecrets: [{ name: ghcr-pull }]` (edge-smoke has none — its image is public).
- `containerPort: 3000` (Next default) not 8080.
- Add a `livenessProbe` alongside readiness (edge-smoke only has readiness). T3: both `httpGet /api/health port: http`. Non-T3: `tcpSocket: { port: <detected> }`.
- `strategy: { type: RollingUpdate }`.
- Resource defaults per CONTEXT: `requests {cpu 25m, memory 128Mi}`, `limits {cpu 500m, memory 512Mi}`.

Label/selector pattern to copy verbatim (edge-smoke lines 4-15):
```yaml
metadata:
  name: {{.Slug}}
  labels:
    app.kubernetes.io/name: {{.Slug}}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: {{.Slug}}
```

---

### `scaffold/templates/gitops/service.yaml.tmpl` (config, request-response)

**Analog:** `gitops/apps/edge-smoke/service.yaml` (full file, 12 lines) — copy verbatim, slug-parameterized.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{.Slug}}
spec:
  selector:
    app.kubernetes.io/name: {{.Slug}}
  ports:
    - name: http
      port: 80
      targetPort: http
```
`port: 80 → targetPort: http` (which resolves to containerPort 3000). No change from analog except slug.

---

### `scaffold/templates/gitops/ingress.yaml.tmpl` (config, request-response)

**Analog:** `gitops/apps/edge-smoke/ingress.yaml` (full file, 17 lines) — copy verbatim, slug-parameterized.

Key fields to preserve: `ingressClassName: traefik`, `host: {{.Slug}}.app.kayage.co`, `pathType: Prefix`, backend `service.port.name: http`.
```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: {{.Slug}}.app.kayage.co
```

---

### `scaffold/templates/gitops/kustomization.yaml.tmpl` (config, transform)

**Analogs:** `gitops/apps/gitops-smoke/kustomization.yaml` (SOPS filename indirection) + `gitops/apps/edge-smoke/kustomization.yaml` (resources list shape).

**CRITICAL — SOPS filename indirection (Pitfall 1 / RESEARCH Pattern 2):** the on-disk secret file is `pull-secret.enc.yaml`, but `resources:` MUST reference the **decrypted** name `pull-secret.yaml`. Verified live: `gitops-smoke/kustomization.yaml` line 5 references `secret.yaml` while the file on disk is `secret.enc.yaml`. The CMP (`infrastructure/kubernetes/argocd/cmp-plugin.yaml`) does `decrypted="${encrypted%.enc.yaml}.yaml"; rm -f "$encrypted"` before `kustomize build`.

Template (adds an `images:` transformer block the analogs don't have — the CI bump target, RESEARCH §4):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - pull-secret.yaml        # decrypted name; file on disk is pull-secret.enc.yaml
images:
  - name: ghcr.io/tkayage/{{.Slug}}
    newTag: latest           # CI rewrites via `kustomize edit set image`
```
The `images[].name` MUST be byte-identical to the Deployment `image:` value (Pitfall 2) or the transformer no-ops.

---

### `scaffold/templates/gitops/pull-secret.yaml.tmpl` (config, file-I/O via SOPS)

**Analogs:** `gitops/apps/gitops-smoke/secret.enc.yaml` (encrypted shape) + `gitops/.sops.yaml` (encryption rule).

Rendered plaintext shape (RESEARCH §5), then `sops --encrypt` → `pull-secret.enc.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-pull
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {"auths":{"ghcr.io":{"username":"tkayage","password":"<CLASSIC_PAT_read:packages>","auth":"<base64(tkayage:PAT)>"}}}
```

Encryption config to reuse from `gitops/.sops.yaml` (verbatim — the scaffolder must write/rely on an identical rule so `apps/<slug>/pull-secret.enc.yaml` matches `.*\.enc\.yaml$`):
```yaml
creation_rules:
  - path_regex: .*\.enc\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq
```
Post-encryption the file carries the same `sops:` metadata block shape as `gitops-smoke/secret.enc.yaml` lines 8-22 (age recipient, `encrypted_regex ^(data|stringData)$`, `version: 3.13.2`). Encrypt via `SOPS_AGE_KEY_FILE=~/.config/homelab/age/keys.txt sops --encrypt`. **Never commit plaintext** (Security Domain).

---

### `scaffold/internal/gitops/gitops.go` (service, file-I/O + git push)

**Analog:** `scripts/gitops-platform.sh` — functions `load_credentials` (19-37), `sync_worktree` (70-84), `publish` (86-94), and the `preflight` push-permission check (46-49).

Port these bash patterns to Go (`os/exec` git per RESEARCH — reuse the exact credential/askpass flow, do NOT adopt go-git):

- **Credentials** (lines 19-26): read `/home/tonny/.config/homelab/github.env`, require `GITHUB_TOKEN`, set `GIT_USERNAME=x-access-token` / `GIT_PASSWORD=$GITHUB_TOKEN`. Note: for the scaffolder's own initial commit this operator token is fine; the CI bump uses a separate `GITOPS_PUSH_TOKEN`.
- **Askpass** (lines 28-36): write a `git-askpass.sh` that echoes username/password by case-match, `chmod 700`, export `GIT_ASKPASS` + `GIT_TERMINAL_PROMPT=0`.
- **Worktree sync** (lines 70-84): clone `https://github.com/tkayage/gitops-homelab.git` to `.local/gitops-homelab` if absent, else `fetch origin main` + `reset --hard origin/main`; set `user.name`/`user.email` on the worktree (analog uses `"Homelab GitOps Operator"` / `gitops@homelab.invalid`).
- **Commit + push** (lines 88-92): `git add apps/<slug>`, skip if `diff --cached --quiet`, else commit + `push origin main`.
- **Push-permission preflight** (lines 46-49): `curl` `api.github.com/repos/tkayage/gitops-homelab` with bearer token, assert `"push": true` before attempting to write.

Constants to reuse: `GITOPS_REPO=tkayage/gitops-homelab`, worktree `.local/gitops-homelab`, `GITHUB_ENV=/home/tonny/.config/homelab/github.env`, `AGE_KEY_FILE=/home/tonny/.config/homelab/age/keys.txt`.

---

### `scaffold/cmd/scaffold/main.go` + `scaffold/internal/{slug,detect,report}` (Go, net-new)

**No in-repo Go analog** (repo has zero Go code today). Nearest structural precedent is `scripts/gitops-platform.sh`:
- **CLI dispatch** (lines 223-231): the `case "${1:-}"` subcommand switch + `usage` error maps to cobra subcommands (`scaffold`, future `remove`).
- **Fail-fast helpers** (lines 16-17): `die()`/`need()` → Go equivalents returning errors / a preflight that checks `git`, `sops`, `kustomize` on PATH before doing work.
- **Reporting** (`status`, line 178-181; `printf` calls throughout): `report.go` (SCAF-05) mirrors this printf-status style — list generated files, the gitops commit pushed, expected URL `https://<slug>.app.kayage.co`, Argo app name `<slug>`, and health-check hint.

External patterns (RESEARCH — use directly, no in-repo analog):
- `slug.go`: regex `^[a-z][a-z0-9-]{1,30}$`, derive from `filepath.Base`, `--slug` override (§7).
- `detect.go`: T3 = `package.json` has `next` dep → generate Dockerfile + health route; else detect existing Dockerfile, parse `EXPOSE`, warn on missing non-root `USER`, TCP probe on resolved port (§8). SCAF-06: never overwrite an existing non-T3 Dockerfile.

---

### `scaffold/templates/{Dockerfile.t3.tmpl,workflow.deploy.yml.tmpl,health.route.ts.tmpl}` (net-new)

**No in-repo analog** — repo has no Dockerfile (except `infrastructure/kubernetes/argocd/Dockerfile.sops`, unrelated), no `.github/workflows`, no TS. Use RESEARCH code examples verbatim as the template bodies:
- Dockerfile: RESEARCH §1 (multi-stage `node:${NODE_VERSION}-alpine` deps→builder→runner, `output: 'standalone'`, `HOSTNAME=0.0.0.0`, non-root uid 1001). Pin base image by digest at plan time.
- Workflow: RESEARCH §3 (two-job `build`→`bump needs:build`; `permissions: {contents: read, packages: write}`; docker `login`/`metadata`/`build-push` actions; bump job checks out `gitops-homelab` with `GITOPS_PUSH_TOKEN`, `kustomize edit set image`, commit+push with rebase-retry loop). **Pin every action to a full commit SHA** (anti-pattern to float `@v6`).
- Health route: RESEARCH §2 (`app/api/health/route.ts`, `GET → 200 ok`).

---

### `scripts/scaffold-verify.sh` (test, batch)

**Analog:** `scripts/gitops-platform.sh` header + helpers. Copy: `#!/usr/bin/env bash` + `set -euo pipefail` (lines 1-2), `ROOT="$(cd ...)"` resolution (line 4), `die()`/`need()` (16-17), and the `case` dispatch (223-231). Behavior: scaffold a fixture into a scratch gitops dir, SOPS round-trip the pull secret, `kustomize build`, dry-run apply. Follows the established `scripts/*-platform.sh` convention (pinned versions, creds from `~/.config/homelab/*.env`).

## Shared Patterns

### SOPS + age encryption
**Source:** `gitops/.sops.yaml` (lines 1-4) + `gitops/apps/gitops-smoke/secret.enc.yaml` (metadata block 8-22)
**Apply to:** `pull-secret.yaml.tmpl` and anywhere the scaffolder writes secrets.
Rule: `path_regex .*\.enc\.yaml$`, `encrypted_regex ^(data|stringData)$`, age recipient `age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq`. Encrypt with the operator age key at `~/.config/homelab/age/keys.txt`. Never commit plaintext secrets.

### CMP decrypt-then-build filename indirection
**Source:** `infrastructure/kubernetes/argocd/cmp-plugin.yaml` (decrypt loop: `decrypted="${encrypted%.enc.yaml}.yaml"; rm -f "$encrypted"`)
**Apply to:** every generated `kustomization.yaml` — reference `pull-secret.yaml`, never `pull-secret.enc.yaml`, in `resources:`.

### ApplicationSet auto-adoption (no per-app Argo change)
**Source:** `gitops/platform/applicationset.yaml` (git-dir generator over `apps/*`, `name`/`namespace = {{path.basenameNormalized}}`, plugin `sops-kustomize-v1.0`, `automated {prune,selfHeal}`, `CreateNamespace=true`)
**Apply to:** the scaffolder relies on this — committing `apps/<slug>/` is sufficient; no ApplicationSet edit, no namespace manifest (auto-created). App name = namespace = `<slug>`.

### GitHub credential + askpass + push-permission flow
**Source:** `scripts/gitops-platform.sh` (`load_credentials` 19-37, preflight push check 46-49, worktree commit/push 86-94)
**Apply to:** `scaffold/internal/gitops/gitops.go` initial commit; the same clone-target (`.local/gitops-homelab`), repo (`tkayage/gitops-homelab`), and `x-access-token` + `GITHUB_TOKEN` askpass mechanism.

### bash script scaffolding conventions
**Source:** `scripts/gitops-platform.sh` lines 1-17, 223-231
**Apply to:** `scripts/scaffold-verify.sh` — shebang, `set -euo pipefail`, `ROOT` resolution, `die`/`need` guards, `case` subcommand dispatch, creds from `~/.config/homelab/*.env`.

## No Analog Found

Files with no close in-repo match (planner uses RESEARCH.md external patterns):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scaffold/templates/Dockerfile.t3.tmpl` | config (build) | batch | No app Dockerfile exists; use RESEARCH §1 |
| `scaffold/templates/workflow.deploy.yml.tmpl` | config (CI) | event-driven | No `.github/workflows` in repo; use RESEARCH §3 |
| `scaffold/templates/health.route.ts.tmpl` | route | request-response | No TS/Next code; use RESEARCH §2 |
| `scaffold/cmd/scaffold/main.go` | controller | request-response | No Go code in repo; cobra pattern from RESEARCH; CLI-dispatch precedent = gitops-platform.sh |
| `scaffold/internal/slug/slug.go` | utility | transform | Net-new; RESEARCH §7 |
| `scaffold/internal/detect/detect.go` | utility | transform | Net-new; RESEARCH §8 |
| `scaffold/go.mod` + `scaffold/internal/*/*_test.go` | config/test | — | Net-new Go module + golden/unit tests |

## Metadata

**Analog search scope:** `gitops/apps/*`, `gitops/platform/`, `gitops/.sops.yaml`, `scripts/*`, `infrastructure/kubernetes/argocd/`
**Files scanned:** 11 read in full (edge-smoke deployment/service/ingress/kustomization, gitops-smoke kustomization/secret.enc.yaml, .sops.yaml, applicationset.yaml, cmp-plugin.yaml, gitops-platform.sh); directory listings for apps/scripts
**Pattern extraction date:** 2026-07-08
