# Feature Research: v1.1 Scaffolder CLI Service

**Domain:** Operator-facing CLI for GitOps-managed homelab service onboarding and updates  
**Researched:** 2026-07-12  
**Confidence:** MEDIUM-HIGH for local project fit; MEDIUM for external ecosystem norms

## Scope

This artifact focuses only on the new v1.1 capabilities:

- Install and run the scaffolder as a dev-server CLI binary.
- Move from T3-first detection to Dockerfile-first detection.
- Offer explicit Dockerfile generation when missing.
- Update existing GitOps-managed services.
- Add/update non-secret env vars and encrypted runtime secrets for existing services.
- Commit changes through the existing GitOps repository flow.

Existing v1.0 features are treated as dependencies, not as features to redesign: GHCR pipeline generation, GitOps app manifests, local/private exposure, explicit public opt-in, T3/generic app support, and SOPS-encrypted secrets.

## Operator Model

The operator should experience the scaffolder as a small, predictable dev-server command:

```bash
scaffold init [--slug app] [--port 3000] [--dockerfile Dockerfile]
scaffold update <slug> [--set KEY=value] [--secret KEY=value|--secret-file KEY=path]
scaffold diff <slug>
scaffold doctor
```

The core UX rule: the CLI prepares and commits desired-state changes; it does not directly deploy, patch live Kubernetes objects, or bypass GitOps. Success means "a validated Git commit was pushed to the GitOps repo"; Argo CD remains responsible for reconciliation.

## Table Stakes

Features users expect. Missing means the CLI feels unsafe, incomplete, or too manual.

| Feature | Why Expected | Complexity | Dependencies | Recommended Behavior |
|---------|--------------|------------|--------------|----------------------|
| Installable dev-server binary | v1.1 explicitly moves from source-only use to a normal operator command. | Low | Go build/release target; dev-server PATH convention; existing Cobra CLI. | Provide `make install-scaffold` or script that builds `scaffold` into a gitignored operator bin dir such as `.local/bin` or `$HOME/.local/bin`; `scaffold version` and `scaffold doctor` confirm the installed binary and required tools. |
| Preflight/doctor command | Operators need failures before state changes, not halfway through SOPS or git push. | Low | Existing preflight for `git`, `sops`, `kustomize`; GitOps repo credentials; SOPS age key; GHCR token path. | `scaffold doctor` checks binary version, PATH tools, app repo cleanliness, GitOps worktree sync, GitHub token env, age recipient/key, and ability to run `kustomize build` on a temp app. |
| Dockerfile-first detection | The platform goal is "anything containerizable"; T3 is only one app type. | Medium | Existing detect package; Dockerfile parser; app repo root detection; port resolution. | Detection order should be: explicit `--dockerfile`, root `Dockerfile`, then "missing Dockerfile" prompt. T3 detection becomes a template hint only when generating a Dockerfile, not the primary classification. |
| Existing Dockerfile read-only validation | Dockerfile is application-owned build logic. Silent rewrites destroy trust. | Low-Medium | Existing SCAF-06 preservation tests; Dockerfile parser. | Inspect for `EXPOSE`, non-root `USER`, and obvious container port; warn but do not mutate. If `EXPOSE` is missing, require `--port` or an interactive answer. |
| Explicit Dockerfile generation when missing | Operator should not leave the tool to hand-write boilerplate, but generation must be opt-in. | Medium | Template system; language/framework hints; app repo write permissions. | On missing Dockerfile, offer: generate a recommended Dockerfile, abort, or continue only with `--dockerfile`. Generated Dockerfile must be shown in diff and committed to the app repo by the operator, not hidden in GitOps. |
| Clear generated Dockerfile ownership | Generated build files need future maintenance by the app repo owner. | Low | App repo git checks. | After generation, print that the Dockerfile is now app-owned and will not be overwritten by future scaffold runs unless an explicit `--replace-dockerfile` feature is later added. |
| Existing service discovery by slug | Updating env/secrets requires finding exactly one service folder. | Medium | GitOps repo worktree; `apps/<slug>/` convention; ApplicationSet directory generator. | `scaffold update fintrack` resolves `apps/fintrack`; refuse if missing, duplicated, or not recognized as scaffold-managed unless `--adopt` is explicitly implemented later. |
| Update mode separate from init mode | New-service onboarding and existing-service edits have different risk profiles. | Low | Cobra subcommands; existing scaffolder orchestration. | Use distinct commands (`init`, `update`, `diff`, `doctor`). Bare `scaffold` may alias `init` for backward compatibility, but update flows should be explicit. |
| Non-secret env var updates | Runtime config often changes after onboarding; hand-editing YAML is the current pain. | Medium | Deployment manifest shape; ConfigMap or direct env convention; kustomize validation. | Store non-secret env in a predictable manifest, preferably `configmap.yaml` consumed by `envFrom` or explicit `env` entries. `--set KEY=value` updates or adds keys idempotently and prints added/changed/unchanged. |
| Secret updates through SOPS | The fintrack runbook shows runtime secret updates are manual and error-prone. | High | SOPS age key; Argo CD SOPS CMP; plaintext temp dir discipline; `*.enc.yaml` convention. | `--secret KEY=value` and `--secret-file KEY=path` decrypt existing secret if present, merge keys, encrypt to `runtime-secret.enc.yaml`, delete plaintext temp files, and refuse to stage plaintext. |
| Key-level diff that redacts secret values | Operators need confidence about what changed without leaking credentials. | Medium | YAML parser; secret merge logic; diff renderer. | Show non-secret values normally; show secret changes as `KEY: added`, `KEY: changed`, `KEY: removed`, or `unchanged`, never the value. |
| Idempotent reruns | CLI scaffolding will be rerun during debugging; duplicate env entries or noisy commits are unacceptable. | Medium | Structured YAML edits; stable sorting; staged-change detection. | Re-running the same update produces no changes and exits cleanly with "already up to date"; no empty commit. |
| Dry-run/diff before commit | GitOps makes commits durable; operator needs a preview. | Medium | Git worktree diff; SOPS redaction; app repo diff for Dockerfile generation. | `--dry-run` performs detection, merge, render, decrypt/encrypt round-trip where needed, validation, and prints a redacted summary without committing or pushing. |
| Local validation before GitOps commit | Broken YAML should never be pushed for Argo to reject. | Medium | Existing `kustomize`, `kubectl --dry-run` verifier, actionlint for workflow changes. | Before commit, run `kustomize build apps/<slug>` with decrypted SOPS temp output where applicable and fail before staging on invalid output. |
| Normal GitOps commit flow | Existing platform decision: GitOps is the deployment interface. | Medium | Existing `gitops.Publish` clone/sync/commit/push code; GitHub token env. | Sync GitOps worktree to `origin/main`, apply changes, stage only `apps/<slug>` encrypted/config files, commit with specific messages, push `main`. Rollback remains `git revert`. |
| Safe git worktree handling | The CLI operates across an app repo and GitOps repo; dirty state can lose work. | Medium | Git status checks; existing git wrapper. | Refuse to operate on dirty app repo when generating Dockerfile/workflow; refuse dirty GitOps worktree unless dirty files are exactly the service being updated and the operator confirms or uses `--allow-dirty-service`. |
| Machine-readable and human-readable output | Solo operator benefits from concise output today and scriptability later. | Low | Report package. | Default output is a short report; `--json` emits slug, command, changed files, changed keys, commit SHA, and validation status. |

## Differentiators

Features that are not strictly required, but would make this feel like a purpose-built homelab platform rather than a YAML helper.

| Feature | Value Proposition | Complexity | Dependencies | Recommendation |
|---------|-------------------|------------|--------------|----------------|
| Interactive guided update flow | Reduces cognitive load for occasional operations. | Medium | TTY detection; prompt library or simple stdin prompts. | In TTY mode, let operator select existing service, choose env vs secret, paste values, review redacted diff, then commit. Keep flags as the canonical automatable path. |
| Runtime config import from env file | Mirrors how fintrack already stores operator-private config. | Medium | Env-file parser; secret classification; validation rules. | Support `--env-file path --as nonsecret|secret|split`. For split mode, classify keys by explicit prefix or prompt; never guess silently for credential-shaped names. |
| Secret value source flexibility | Avoids leaking secrets into shell history. | Medium | Secure prompt; file reads; stdin. | Support `--secret KEY` prompting hidden input, `--secret-file KEY=path`, and `--secret-stdin KEY`. Warn against `--secret KEY=value` in interactive shells but allow for scripts if needed. |
| Managed service marker | Makes update/adoption decisions safer. | Low | Manifest labels/annotations. | Add `homelab.kayage.co/managed-by: scaffold` and `homelab.kayage.co/scaffold-version` to generated resources; update mode can refuse unmanaged folders by default. |
| Config schema hints | Prevents typos in required runtime keys for known services. | Medium | Optional per-service metadata file. | Allow `apps/<slug>/scaffold.yaml` to declare expected env and secret keys, required/optional status, and restart sensitivity. Start with optional metadata; do not require it for generic apps. |
| Redacted rollback hints | Closes the loop after commit without becoming a deploy tool. | Low | Commit SHA; Argo app name convention. | After push, print `git -C <gitops> revert <sha>` and `kubectl -n argocd get application <slug>` commands. Keep it informational. |
| Dockerfile template profiles | Generates better defaults without reintroducing T3 lock-in. | Medium | Template catalog; detection hints. | Offer profiles such as `node-standalone`, `static-nginx`, `go-binary`, and `generic`. Auto-suggest, but require explicit acceptance. |
| Port inference explanation | Operators need to know why a Service targetPort changed. | Low | Dockerfile parser; report package. | Report whether port came from `--port`, `EXPOSE`, T3 default, or prompt. This is useful when debugging ingress/service mismatch. |
| Adopt existing GitOps service | Lets the tool help with manually-created services later. | High | Manifest normalization; ownership markers; conflict detection. | Defer unless needed. If built, require an explicit `scaffold adopt <slug>` that validates expected file layout and adds management metadata in a separate commit. |

## Anti-Features

Features to explicitly not build for this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Imperative live Kubernetes patching | It splits source of truth and conflicts with the platform's GitOps contract. | Write/commit desired state; let Argo CD reconcile. |
| Silent Dockerfile overwrite | Existing Dockerfiles are application-owned and may encode non-obvious build requirements. | Read-only inspect existing Dockerfiles; generate only when missing and accepted. |
| T3-only detection path | v1.1 is explicitly Dockerfile-first and app-agnostic. | Treat T3 as a Dockerfile generation/profile hint, not as the primary app kind. |
| Secret values in CLI output, git diff, logs, or commit messages | Leaks credentials into terminal scrollback, CI logs, shell history, and git metadata. | Redact values everywhere; report key-level actions only. |
| Plaintext secret files in the GitOps worktree | Easy to accidentally stage; existing project already forbids this. | Use private temp dirs, encrypt immediately, delete plaintext, and hard-fail if `*.yaml` plaintext secret files are staged. |
| Automatic secret classification by key name only | False negatives leak secrets; false positives create confusing runtime config. | Use explicit flags (`--set` vs `--secret`) and optionally warn on credential-shaped keys passed as non-secret. |
| A web UI or dashboard for updates | Too much surface for a solo operator milestone. | CLI with good reports, dry-run, and doctor. |
| PR-based approval workflow | Useful for teams, unnecessary friction for a one-person homelab. | Direct commit/push to GitOps `main`, preserving rollback by git revert. |
| Replacing SOPS with a new secret backend | SOPS is already validated in the platform and Argo CD flow. | Extend the current SOPS workflow for runtime secrets. |
| Full Dockerfile lint/refactor system | Dockerfile quality automation can sprawl quickly. | Warn on a small set of deployment-critical checks: port and non-root user. Defer hadolint integration. |
| Managing app runtime databases in this milestone | Env/secrets update may carry DB URLs, but DB provisioning is a separate platform feature. | Accept supplied connection values; do not create databases/users yet. |
| Public exposure changes bundled into env updates | Public/private routing is already a sensitive, explicit opt-in feature. | Keep exposure changes as a separate command/flag with clear confirmation. |

## Feature Dependencies

```text
Installable CLI binary
  -> existing Go/Cobra scaffold module
  -> dev-server PATH convention
  -> version/doctor reporting

Dockerfile-first init
  -> app repo git root detection
  -> Dockerfile parser
  -> app repo file rendering
  -> existing workflow/GHCR templates
  -> existing GitOps manifest publisher

Existing service update
  -> GitOps repo clone/sync/commit/push
  -> apps/<slug>/ folder convention
  -> scaffold-managed metadata or conservative layout detection
  -> kustomize validation

Non-secret env updates
  -> stable ConfigMap/env manifest convention
  -> Deployment consumes ConfigMap/env entries
  -> structured YAML edits

Encrypted secret updates
  -> SOPS age key available on dev server
  -> Argo CD SOPS CMP already deployed
  -> runtime-secret.enc.yaml convention
  -> plaintext temp-file cleanup and staged plaintext guard

Rollback/recovery UX
  -> Git commit SHA from update
  -> existing GitOps rollback practice: git revert
  -> Argo CD application naming convention
```

## MVP Recommendation

Prioritize:

1. **Binary install + doctor**: build/install command, `scaffold version`, `scaffold doctor`, and hard preflight before mutating anything.
2. **Dockerfile-first init**: detect existing Dockerfile read-only, infer/report port, warn on missing non-root user, prompt/generate Dockerfile when missing, and preserve existing Dockerfiles byte-for-byte.
3. **Update existing service config**: `scaffold update <slug> --set KEY=value` with idempotent structured YAML edits, redacted diff, kustomize validation, GitOps commit, and no empty commit.
4. **Update existing service secrets**: `--secret`, `--secret-file`, encrypted merge into `runtime-secret.enc.yaml`, plaintext staging guard, redacted report, and GitOps commit.
5. **Dry-run/diff**: available for both init and update before committing.

Defer:

- `scaffold adopt`: valuable but high-risk because unmanaged manifests may not match scaffold assumptions.
- Dockerfile lint/refactor integrations: start with deployment-critical checks only.
- PR workflows: unnecessary for the solo-operator GitOps flow.
- Web UI: not needed for this milestone.
- DB provisioning or Zitadel client provisioning: adjacent but outside the requested env/secrets update flow.

## UX Recommendations

### Command Shape

Use explicit verbs:

- `scaffold init`: onboard current app repo.
- `scaffold update <slug>`: change desired state for an existing GitOps service.
- `scaffold diff <slug>`: show current managed config and redacted secret metadata.
- `scaffold doctor`: verify local operator prerequisites.

Avoid overloading bare `scaffold` for update behavior. Backward-compatible bare `scaffold` can continue to mean `init`.

### Update Report

Every successful update should end with a compact report:

```text
Service: fintrack
GitOps path: apps/fintrack
Non-secret env: 2 added, 1 changed, 4 unchanged
Secrets: 1 added, 2 changed, values redacted
Validation: kustomize build OK, plaintext secret guard OK
Commit: abc1234 deploy(fintrack): update runtime config
Next: Argo CD will reconcile from GitOps; rollback with git revert abc1234
```

### Error Style

Errors should name the operator action, not just the failing implementation detail:

- Good: `refusing to update fintrack: apps/fintrack is not scaffold-managed; run scaffold adopt first or edit GitOps manually`
- Good: `missing Dockerfile: generate a node-standalone Dockerfile, pass --dockerfile, or abort`
- Good: `refusing to stage plaintext secret file apps/fintrack/runtime-secret.yaml`
- Bad: `open runtime-secret.yaml: no such file or directory`

## Implications for Roadmap

- Build the binary/doctor first because every later feature depends on trustworthy local prerequisites.
- Convert detection before expanding update flows; otherwise update behavior inherits T3-first assumptions.
- Establish the runtime config file convention before implementing env/secret flags. The hard design decision is where non-secret env and encrypted secret manifests live and how the Deployment consumes them.
- Implement non-secret env updates before secret updates. It proves service discovery, YAML mutation, diffing, validation, and GitOps commit flow without SOPS merge complexity.
- Secret updates need their own verification phase because the failure modes are severe: plaintext leakage, corrupted encrypted YAML, wrong age recipient, and broken Argo CMP decrypt.

## Sources

- Local project context: `.planning/PROJECT.md`, `scaffold/README.md`, `docs/runbooks/fintrack-deployment.md`, existing `scaffold/internal/*` contracts (HIGH confidence for project fit).
- Argo CD docs: Git repository as desired-state source of truth and Kubernetes manifest reconciliation (MEDIUM, official docs via websearch).
- Flux SOPS guide and Red Hat GitOps secret guidance: encrypted Kubernetes secrets can be safely stored in Git when decrypted by automation at reconciliation time (MEDIUM, verified across sources).
- Kubernetes Kustomize docs: ConfigMaps and Secrets are standard ways to provide app configuration to Pods from declarative manifests (MEDIUM, official docs via websearch).
- Docker docs and container security guidance: Dockerfiles should be explicit, maintainable, minimal, and reviewed as app-owned build definitions (MEDIUM, verified across sources).
- CLI Guidelines: CLIs should support predictable commands, scriptable output, useful errors, and dry-run style inspection for risky operations (MEDIUM, community guidance).

