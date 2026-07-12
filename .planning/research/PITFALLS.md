# Pitfalls Research: v1.1 Scaffolder CLI Service

**Domain:** Homelab GitOps scaffolder that updates existing Kubernetes services and SOPS-encrypted secrets  
**Researched:** 2026-07-12  
**Overall confidence:** MEDIUM  
**Scope:** Common mistakes, security risks, and operational failure modes when adding CLI binary mode, Dockerfile-first detection, Dockerfile generation, existing-service updates, env var updates, encrypted secret updates, and GitOps commits.

## Executive Findings

The riskiest change in v1.1 is not installing the scaffolder as a CLI; it is letting the CLI mutate existing GitOps-managed services. Creation workflows can be template-driven. Update workflows must preserve human edits, Argo CD sync semantics, SOPS metadata, generated resource naming, and rollout behavior. Treat every update as a deterministic Git patch with preflight validation, not as "edit some YAML."

Secret handling is the sharpest security boundary. SOPS supports safe tree-level edits and Kubernetes-focused partial encryption, but a CLI can still leak plaintext through logs, shell history, temp files, decrypted diffs, wrong working directories, or incorrect `.sops.yaml` rule selection. The CLI should never ask users to paste secrets into command arguments, never write decrypted files in place, and never commit a file unless it proves secret values are encrypted.

GitOps reconciliation creates a delayed failure mode: the CLI can produce a clean local commit that later causes Argo CD to prune, fail sync, leave pods running with stale env vars, or silently drift because the wrong object was edited. The update flow needs render validation, semantic diffing, commit boundaries, and a post-commit reconciliation check.

## Critical Pitfalls

### Pitfall 1: Non-idempotent YAML mutation corrupts existing services

**What goes wrong:** Re-running the CLI duplicates env entries, rewrites unrelated annotations, drops manually added fields, changes list ordering in noisy ways, or replaces an existing overlay with scaffold defaults.

**Why it happens:** Update logic treats YAML as text or as a newly generated template instead of loading existing Kubernetes objects, applying targeted structural changes, and preserving unknown fields. Existing services are not identical to scaffold output after weeks of operation.

**Consequences:** Git diffs become unreviewable, Argo CD applies unintended changes, rollback is hard, and the operator loses trust in the scaffolder.

**Prevention:**
- Parse YAML into Kubernetes-aware structures and patch only owned fields.
- Make every update operation repeatable: second run should produce no diff.
- Maintain explicit ownership markers for scaffolder-managed blocks where useful, but never delete unowned fields.
- Validate with `kubectl kustomize` or equivalent render before commit.
- Add regression tests using a service manifest with extra annotations, probes, resources, ingress settings, and manually added env vars.

**Detection:** Re-running the same command changes Git; diffs include unrelated formatting or field churn; manually added manifest fields disappear.

**Phase to address:** Existing-service discovery/update core.

### Pitfall 2: Secret values leak during SOPS update flow

**What goes wrong:** Plaintext secrets appear in process lists, shell history, terminal logs, debug logs, temp files, Git diffs, crash reports, or a accidentally committed cleartext Kubernetes Secret.

**Why it happens:** The CLI accepts secrets as command-line args, decrypts files in place, shells out unsafely, prints command traces, or writes intermediate decrypted YAML. SOPS can safely edit encrypted trees, but only if the caller controls IO and avoids plaintext persistence.

**Consequences:** Git history or local machine artifacts contain credentials. Rotating the secret may require rotating downstream services, GHCR tokens, database passwords, or API credentials.

**Prevention:**
- Accept secret values through hidden prompt, stdin, or `--value-file`, not positional args.
- Prefer `sops set --value-stdin` / structured SOPS operations over full-file decrypt/edit/re-encrypt.
- If full decrypt is unavoidable, use memory-only handling or secure temp files with cleanup traps and restrictive permissions.
- Redact secret values from logs and errors by default.
- Add a pre-commit validation step that fails if Kubernetes Secret `data`/`stringData` values are plaintext under the repository's SOPS policy.
- Never enable `set -x` around secret handling.

**Detection:** `git diff` shows readable secret values; shell history contains secret-looking tokens; temp directories contain decrypted YAML; CLI debug logs include submitted values.

**Phase to address:** SOPS secret update flow.

### Pitfall 3: Wrong `.sops.yaml` rule or working directory encrypts with the wrong recipients

**What goes wrong:** The CLI creates or updates a secret file that cannot be decrypted by the GitOps reconciler or cluster-side decryptor, or encrypts values for the wrong environment.

**Why it happens:** SOPS discovers `.sops.yaml` from the current working directory and applies the first matching creation rule. A dev-server CLI may be launched from the app repo while mutating the GitOps repo, so relative rule matching can be wrong.

**Consequences:** Argo CD sync fails on secret decryption, or worse, the wrong recipient set can decrypt the secret.

**Prevention:**
- Always run SOPS from the GitOps repo root or pass explicit config/recipient parameters.
- Resolve and display the target secret path before mutation.
- Validate decryptability after write using the same key path expected by the operator/reconciler.
- Require a `.sops.yaml` match for new secret files; fail closed if no rule matches.
- Keep environment-specific secret paths explicit.

**Detection:** New encrypted file has unexpected SOPS metadata; `sops -d` fails locally or in reconciliation; same command behaves differently from different working directories.

**Phase to address:** CLI runtime/install + SOPS update flow.

### Pitfall 4: ConfigMap/Secret changes do not restart workloads

**What goes wrong:** The GitOps repo and Kubernetes Secret/ConfigMap update successfully, but the running app keeps using old env vars until a manual rollout or pod restart.

**Why it happens:** Environment variables are resolved when a container starts. Updating a referenced Secret or ConfigMap does not automatically update env vars in already running containers. Kustomize-generated names can trigger rollout when references change, but direct Secret/ConfigMap edits may not.

**Consequences:** Operator thinks the update worked; app behavior remains stale; emergency secret rotation is incomplete.

**Prevention:**
- Decide the platform pattern: generated ConfigMaps/Secrets with content-hash names, or explicit rollout annotation bumps on Deployment pod templates.
- For this CLI, add/update a deterministic `scaffolder.homelab.dev/config-revision` or checksum annotation on the pod template whenever env/secret inputs change.
- Include rollout status/reconciliation verification after commit.
- Document when immutable Secret/ConfigMap resources require replacement plus pod recreation.

**Detection:** Argo CD shows Synced/Healthy but pod start time predates the secret/env change; app logs show old config; rollout history has no new ReplicaSet.

**Phase to address:** Env var update flow + SOPS secret update flow.

### Pitfall 5: Secret/non-secret classification is wrong

**What goes wrong:** Credentials are stored as non-secret env vars in a Deployment or ConfigMap, or harmless config is put into encrypted Secret files, making review and operations harder.

**Why it happens:** The CLI asks "env var or secret?" without guardrails, or classifies only by user input. Common keys such as `DATABASE_URL`, `TOKEN`, `CLIENT_SECRET`, `PASSWORD`, and API keys are easy to mishandle.

**Consequences:** Sensitive values become visible in Git, Argo CD UI, Kubernetes object output, or logs. Conversely, over-encryption obscures routine config changes.

**Prevention:**
- Add name-based warnings for likely secret keys and require explicit confirmation to store them as non-secret.
- Default likely-sensitive keys to SOPS-backed Kubernetes Secret references.
- Keep non-secret env vars in a reviewed ConfigMap/Deployment section and secrets in SecretKeyRefs.
- Never copy secret values into ConfigMaps for interpolation.

**Detection:** Git grep finds token-like values in plain manifests; `kubectl get cm -o yaml` contains credentials; app env config mixes cleartext `*_SECRET` keys with non-secret values.

**Phase to address:** Env var update UX + secret update UX.

### Pitfall 6: Update flow accidentally changes Argo CD prune/self-heal blast radius

**What goes wrong:** A scaffolder update changes sync options, finalizers, labels, resource names, or Application paths. Argo CD then prunes resources, stops tracking a service, or starts self-healing changes the operator expected to make manually.

**Why it happens:** The CLI treats Application manifests and app resource manifests as owned templates, not as operational policy. Argo CD automated sync, pruning, self-heal, and finalizers are high-impact settings.

**Consequences:** Resources are deleted or orphaned from one commit. In the worst case, a directory rename or path error makes Argo CD see desired resources as removed.

**Prevention:**
- Do not modify Argo CD Application sync policy during ordinary service updates.
- Protect resource identity fields: namespace, kind, name, selector labels, Argo tracking labels/annotations, and app path.
- Render and diff before commit; flag deletes/prunes as a separate confirmation step.
- Fail if the rendered object set has fewer resources than before unless the command is explicitly a delete command.

**Detection:** Local diff changes `Application.spec.syncPolicy`, finalizers, app path, selectors, or resource names; Argo CD shows unexpected prune operations after commit.

**Phase to address:** Existing-service update core + GitOps commit flow.

### Pitfall 7: Kustomize generator names are edited as if they were stable object names

**What goes wrong:** The CLI updates a generated Secret or ConfigMap name directly, breaks Deployment references, or creates a duplicate object instead of updating the generator input.

**Why it happens:** Kustomize appends content hashes to generated ConfigMap/Secret names and rewrites references at render time. Raw YAML names are not always the names applied to the cluster.

**Consequences:** Pods reference missing config, Argo CD sync fails, or stale generated objects accumulate.

**Prevention:**
- Detect whether a service uses Kustomize generators before editing.
- Update generator sources (`configMapGenerator`, `secretGenerator`, env files, literals, or patch files), not rendered names.
- Always compare rendered output before and after mutation.
- Do not mix SOPS-managed Secret manifests and Kustomize `secretGenerator` unless the platform explicitly supports that pattern.

**Detection:** Rendered names contain hash suffixes; CLI-created Secret name lacks the suffix; Deployment references a name that does not exist in rendered output.

**Phase to address:** Existing-service discovery/update core.

### Pitfall 8: Git commit flow publishes partial or invalid state

**What goes wrong:** The CLI commits a Dockerfile but not matching manifests, commits an encrypted secret without the Deployment reference, commits manifests that do not render, or pushes while the GitOps repo has uncommitted operator changes.

**Why it happens:** Update commands are implemented as independent file writes and immediate commits instead of a transaction-like plan/apply/verify flow.

**Consequences:** Argo CD reconciles a broken intermediate state; rollback requires manual Git surgery; unrelated user changes are swept into scaffolder commits.

**Prevention:**
- Require a clean Git worktree unless the user explicitly includes known files.
- Stage only files the scaffolder changed.
- Run pre-commit checks: YAML parse, Kustomize render, Kubernetes schema validation where available, SOPS decrypt/metadata check, secret plaintext scan, and semantic diff summary.
- Use one logical commit per service update.
- On failure, leave files unstaged and print exact recovery steps.

**Detection:** Commit includes unrelated files; Argo CD sync fails immediately after CLI push; `git status` was dirty before the command; commit message does not explain service/key changes.

**Phase to address:** GitOps commit flow.

### Pitfall 9: Dockerfile-first detection overwrites intentional container behavior

**What goes wrong:** The CLI generates or replaces a Dockerfile for a project that already has an intentional container contract, private base image, special build args, healthcheck, or runtime command.

**Why it happens:** Replacing T3 detection with Dockerfile-first detection can become "Dockerfile template wins." Existing projects may be containerizable but not standard Node/T3 apps.

**Consequences:** CI builds succeed but runtime behavior breaks; image tags point to a container that lacks required files, env, ports, or health checks.

**Prevention:**
- If a Dockerfile exists, inspect and preserve it; do not overwrite.
- If missing, generate a Dockerfile only after showing the detected project type and proposed runtime port/build command.
- Keep Dockerfile generation separate from GitOps service update until the image builds locally or in CI.
- Stamp generated files with a small marker so future update logic can distinguish generated defaults from user-owned files.

**Detection:** Existing Dockerfile diff replaces large sections; generated Dockerfile assumes npm/T3 where project uses another runtime; Kubernetes port does not match Dockerfile/app port.

**Phase to address:** Dockerfile-first detection + Dockerfile generation.

### Pitfall 10: CLI binary runs with ambiguous repo context

**What goes wrong:** The scaffolder edits the app repo instead of the GitOps repo, finds the wrong service by directory name, uses a stale clone, or commits to the wrong branch/remote.

**Why it happens:** As an installed dev-server binary, the CLI can be launched from anywhere. The old operator workflow likely assumed a known working directory.

**Consequences:** Changes are lost, committed to the wrong repository, or never reconciled by Argo CD.

**Prevention:**
- Require explicit GitOps repo path config on install, persisted in a small config file.
- At runtime, verify repo remote, branch, and root marker files before mutation.
- Resolve service identity from GitOps metadata, not just app directory basename.
- Print target app repo, GitOps repo, service path, branch, and changed files before apply.

**Detection:** CLI output shows relative paths only; `git remote -v` does not match expected GitOps repo; Argo CD watches a different branch than the CLI commits to.

**Phase to address:** CLI install/runtime configuration.

## Moderate Pitfalls

### Pitfall 11: Environment variable names accepted by CLI are ignored by Kubernetes

**What goes wrong:** The CLI adds keys that Kubernetes cannot expose as env vars, so pods start without the expected variables.

**Prevention:** Validate env names against Kubernetes env var restrictions before writing. Fail fast on invalid names rather than relying on Kubernetes warnings.

**Phase to address:** Env var update flow.

### Pitfall 12: Immutable Secrets or ConfigMaps are treated as mutable

**What goes wrong:** Updating `.data` fails because the object is immutable, or deleting/recreating it leaves existing pods mounted to old object state.

**Prevention:** Detect `immutable: true` in rendered manifests. Require explicit replace workflow and rollout.

**Phase to address:** Env var update flow + secret update flow.

### Pitfall 13: Secret update code creates RBAC pressure to list all namespace secrets

**What goes wrong:** The CLI or validation tooling asks for broad Kubernetes secret read permissions. Anyone with list/watch on Secrets in a namespace can effectively read all secret data.

**Prevention:** Prefer Git-only validation. If cluster validation is needed, scope it to non-secret metadata and Argo CD status, not `kubectl get secrets -o yaml`.

**Phase to address:** Reconciliation verification.

### Pitfall 14: Generated commits hide security-relevant changes

**What goes wrong:** A commit says "update service" but changes public exposure, secrets, env vars, image pull behavior, or ingress hostnames.

**Prevention:** Generate structured commit messages listing service name, changed manifest files, env keys added/updated, secret keys added/updated without values, and whether rollout annotations changed.

**Phase to address:** GitOps commit flow.

### Pitfall 15: Existing-service detection chooses the wrong service

**What goes wrong:** The CLI updates `fintrack` when the operator meant `fintrack-worker`, or updates a fork/staging path.

**Prevention:** Match by explicit service metadata and require confirmation when multiple candidates share names, repos, images, hosts, or labels.

**Phase to address:** Existing-service discovery/update core.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| CLI binary install/runtime | Ambiguous GitOps repo, branch, or working directory | Install-time config; runtime repo/branch/root validation; explicit target summary |
| Dockerfile-first detection | Overwriting intentional Dockerfile behavior | Never overwrite existing Dockerfile; separate detection, generation, and service update |
| Dockerfile generation | Generated image does not match Kubernetes port/env/start command | Show detected port/start command; require build verification before GitOps commit |
| Existing-service discovery | Wrong service selected | Match by metadata; handle duplicates with explicit selection |
| Existing-service update | Non-idempotent YAML churn | Structural patching; second-run no-diff tests; render diff before commit |
| Non-secret env vars | Invalid names or sensitive values stored as cleartext | Kubernetes env-name validation; likely-secret classifier and confirmation |
| SOPS secret updates | Plaintext leakage or wrong recipients | Hidden input/stdin; SOPS set operations; repo-root `.sops.yaml` validation; decryptability check |
| GitOps commit | Partial invalid commit reconciled by Argo CD | Clean worktree requirement; staged-file allowlist; render/SOPS/schema checks before commit |
| Reconciliation check | Argo CD reports Synced but app still uses old env | Rollout checksum annotation; verify new ReplicaSet/pod start after env/secret changes |

## Recommended Prevention Strategy

1. Build the update flow as `plan -> apply files -> validate -> commit -> observe`, not as direct file edits.
2. Use structural YAML/Kubernetes patching and preserve unknown fields.
3. Define owned surfaces: env var entries, secret key references, generated Dockerfile marker, rollout checksum annotation, and commit metadata.
4. Treat SOPS as a security subsystem: controlled working directory, no plaintext args, no in-place decrypt, encrypted-value validation, decryptability check.
5. Make idempotency a test requirement for every update command.
6. Validate rendered manifests before Git commit and compare object sets to catch accidental deletes.
7. Verify reconciliation after commit: Argo CD sync status, app health, and rollout status when env/secret inputs changed.

## Sources

- Argo CD official docs: automated sync lets pipelines commit to the Git tracking repo instead of calling Argo CD directly; pruning is disabled by default as a safety mechanism; self-heal/prune/allow-empty alter reconciliation behavior. <https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/>
- Argo CD official docs: sync options include no-prune, prune confirmation, prune-last, server-side apply, and shared-resource protections; these options affect deletion and ownership behavior. <https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/>
- SOPS official docs: supports YAML/JSON/ENV/INI tree encryption, age recipients, `.sops.yaml` creation rules, `set`/`unset`, `--value-stdin`, and encrypted regex for Kubernetes `data`/`stringData`. <https://getsops.io/docs/>
- SOPS official docs, age identities and config file behavior: age key lookup paths, recipient rules, `updatekeys`, and `.sops.yaml` rule selection. <https://getsops.io/docs/usage/identities/age/> and <https://getsops.io/docs/usage/identities/config-file/>
- SOPS official docs, common operations/security: in-place encrypt/decrypt behavior, tree path edits, cleartext diff support, and security model. <https://getsops.io/docs/usage/common-operations/> and <https://getsops.io/docs/security/>
- Kubernetes official docs: Secrets can be edited unless immutable; immutable Secrets/ConfigMaps cannot be mutated and require delete/recreate plus pod recreation; broad list/watch Secret permissions expose namespace secret data. <https://kubernetes.io/docs/concepts/configuration/secret/>
- Kubernetes official docs: ConfigMap keys used as env vars must satisfy env-var naming restrictions; immutable ConfigMaps cannot be mutated. <https://kubernetes.io/docs/concepts/configuration/configmap/>
- Kubernetes official docs: Kustomize generators create ConfigMaps/Secrets from files/env/literals and add hash-suffixed generated names in rendered output. <https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/>

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| SOPS secret handling | MEDIUM | Based on official SOPS docs; exact implementation risk depends on current scaffolder code. |
| GitOps reconciliation | MEDIUM | Based on official Argo CD docs and established GitOps patterns; local sync policy must be inspected during implementation. |
| Kubernetes env/secret rollout | MEDIUM | Based on official Kubernetes docs; rollout mechanism depends on the repo's manifest style. |
| Kustomize/idempotency | MEDIUM | Based on official Kubernetes/Kustomize docs; risk depends on whether existing services use generators, patches, or plain manifests. |

## Implications for Roadmap

- Put **CLI runtime context validation** before update features. A binary that can run from anywhere must first prove it knows the app repo, GitOps repo, branch, service path, and Argo-watched target.
- Put **existing-service discovery and idempotent patching** before env/secret update UX. Secret updates are unsafe until the scaffolder can patch existing manifests without unrelated churn.
- Put **SOPS update flow** in its own phase or protected subphase with explicit security tests.
- Put **GitOps commit and reconciliation verification** after file mutation works but before considering the milestone done. The acceptance test should include a real existing service update, a no-op second run, and an Argo CD health/sync check.
