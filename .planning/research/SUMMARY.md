# v1.1 Scaffolder CLI Service Research Summary

**Project:** Homelab Deploy Platform
**Milestone:** v1.1 Scaffolder CLI Service
**Domain:** Operator-facing Go CLI for GitOps-managed container service onboarding and updates
**Researched:** 2026-07-12
**Confidence:** MEDIUM-HIGH

## Key Findings

v1.1 should extend the existing Go/Cobra scaffolder into a normal dev-server CLI binary rather than creating a new service, daemon, web UI, or imperative deployment tool. The CLI should remain file- and GitOps-oriented: inspect an app repository, generate or validate a Dockerfile, mutate the GitOps repository, encrypt runtime secrets with SOPS, validate rendered manifests, commit, and push. Argo CD remains responsible for reconciliation.

The strongest shared recommendation is to split the scaffolder into explicit workflows: `init` for new service onboarding, `update` for existing GitOps services, `diff` or dry-run for preview, and `doctor` for local prerequisite checks. The bare command can remain an init-compatible alias for backward compatibility, but update behavior should require an explicit verb because it mutates existing desired state.

**Recommended stack decisions:**
- Keep Go and Cobra for the CLI; add install/version/doctor support around the existing module.
- Keep shelling out to system `git` and `sops`; do not add `go-git`, SOPS internals, client-go, Helm SDK, Docker SDK, or a daemon.
- Add `sigs.k8s.io/kustomize/kyaml` for Kubernetes-aware YAML edits that preserve existing service shape.
- Optionally add `golang.org/x/term` only if interactive prompts are required; flag-driven flows should remain canonical.
- Continue using GHCR, Argo CD ApplicationSet, k3s, Kustomize-style app directories, and SOPS+age as the deployment substrate.

**Must-have product behavior:**
- Installable `scaffold` binary on the dev server, with `version` and `doctor`.
- Dockerfile-first detection: explicit `--dockerfile`, then root `Dockerfile`, then an explicit missing-Dockerfile branch.
- Existing Dockerfiles are read-only inputs; inspect for `EXPOSE`, non-root `USER`, and port hints, but never silently rewrite.
- Missing Dockerfiles can be generated only with operator acceptance or explicit flags, and generated files become app-owned.
- Existing services are discovered by slug under `apps/<slug>/` and updated in place without full directory re-render.
- Non-secret env vars are added or updated idempotently through ConfigMap or existing Deployment env conventions.
- Runtime secrets are merged into SOPS-encrypted Kubernetes Secret manifests with values redacted from all output.
- Every mutating command supports preview/dry-run, local validation, scoped staging, a meaningful GitOps commit, and no empty commit on no-op reruns.

**Critical pitfalls to design around:**
- Do not re-render existing app directories; patch specific Kubernetes resources and preserve custom fields, PVCs, daemon-only services, annotations, and missing Service/Ingress cases.
- Do not leak secret values through CLI args, logs, diffs, temp files, process lists, shell history, or plaintext files in the GitOps worktree.
- Run SOPS from the GitOps repo root or with explicit config/recipient handling so `.sops.yaml` rules and recipients are correct.
- Env/secret changes may not restart pods automatically; update a deterministic pod-template checksum/revision annotation when runtime config changes.
- Validate env var names, warn on likely-secret keys passed as non-secret, and keep secret classification explicit.
- Stage only known changed files under one service directory and reject dirty or ambiguous GitOps worktrees unless an explicit safe override exists.

## Implications for Roadmap

Suggested phase structure:

1. **CLI Runtime and Preflight**
   - **Rationale:** An installed binary can run from any directory, so it must first prove repo context, branch, credentials, SOPS, kustomize, and GitOps target before it can safely mutate files.
   - **Delivers:** `scaffold` install path, `version`, `doctor`, explicit command skeleton, config for GitOps repo path, target summary, and shared preflight/reporting.
   - **Avoids:** Ambiguous working directory, wrong branch/remote, partial state changes, and late SOPS/git failures.
   - **Research flag:** Low. Standard Cobra/install/preflight patterns; implementation should inspect local repo conventions.

2. **GitOps Worktree Primitives and Service Loader**
   - **Rationale:** Update features depend on safe, reusable GitOps operations and read-only service discovery before any patching.
   - **Delivers:** Extracted sync/stage/commit/push helpers, changed-file detection, `apps/<slug>/` resolver, kustomization/resource loader, managed-service metadata handling, and an inspect/diff foundation.
   - **Avoids:** Wrong service selection, unrelated file commits, re-rendering existing services, and Argo CD prune/self-heal blast radius.
   - **Research flag:** Medium. Needs careful validation against current fixtures and live-shaped services such as `fintrack`.

3. **Dockerfile-First Init Flow**
   - **Rationale:** Creation should be made container-contract-first before update flows grow, otherwise T3-first assumptions continue to leak into v1.1.
   - **Delivers:** Dockerfile-first detection, `EXPOSE`/port reporting, non-root warning, missing-Dockerfile state, explicit generation flags/prompts, conservative templates, and preservation tests proving existing Dockerfiles are unchanged.
   - **Avoids:** Silent Dockerfile overwrite, T3 lock-in, mismatched Kubernetes ports, and hidden app-owned build changes.
   - **Research flag:** Low-Medium. Dockerfile semantics are documented; exact template profiles need local fixture validation.

4. **Non-Secret Runtime Config Updates**
   - **Rationale:** This proves structural YAML patching, idempotency, dry-run diffing, validation, scoped staging, and commit flow without SOPS complexity.
   - **Delivers:** `scaffold update <slug> --set KEY=value`, ConfigMap or existing env upsert, duplicate-key behavior, env-name validation, likely-secret warning, redacted/structured report, kustomize validation, and no-op second run.
   - **Avoids:** YAML churn, invalid Kubernetes env names, credentials in ConfigMaps, stale pods due to missing rollout annotation, and noisy commits.
   - **Research flag:** Medium. Phase planning should inspect existing manifest styles and decide the canonical ConfigMap/env convention.

5. **Encrypted Runtime Secret Updates**
   - **Rationale:** Secret handling has the highest security and operational risk and should build on a proven service loader, patcher, validator, and commit path.
   - **Delivers:** `--secret`, `--secret-file`, and ideally stdin/hidden prompt inputs; decrypt-or-create runtime Secret; merge keys; re-encrypt to `runtime-secret.enc.yaml`; validate `.sops.yaml` rule/recipient/decryptability; plaintext guard; redacted key-level diff; rollout annotation; scoped GitOps commit.
   - **Avoids:** Plaintext leaks, wrong SOPS recipients, corrupted ciphertext, `.enc.yaml` kustomization references, immutable Secret surprises, and secret values in commit metadata.
   - **Research flag:** High. Use `$gsd-plan-phase --research-phase` here to validate exact SOPS CLI operations, temp-file discipline, and current Argo CMP expectations.

6. **Final UX, Dry-Run, Validation, and Reconciliation Checks**
   - **Rationale:** Once mutation paths work, the milestone needs operator polish and end-to-end confidence, not new deployment mechanics.
   - **Delivers:** Stable command names, dry-run/diff across init/update, JSON output, completion if useful, compact reports, commit SHA/rollback hints, render/object-set validation, and optional post-push Argo health/sync checks.
   - **Avoids:** Hidden destructive changes, unreviewable commits, Argo CD delayed failures, and app config changes that appear synced but do not roll pods.
   - **Research flag:** Medium. Reconciliation checks depend on current Argo naming, access, and sync policy.

**Phase ordering rationale:** Build the safety rails first, then the GitOps mutation substrate, then Dockerfile-first create behavior, then progressively riskier update operations. Non-secret env updates should come before encrypted secret updates because they exercise discovery, YAML patching, validation, idempotency, and commit flow without exposing credentials. Secret updates deserve a dedicated phase with security tests.

## Requirement Guidance

Translate the research into requirements with these acceptance criteria:

- **CLI binary:** The operator can install and run `scaffold` from the dev server PATH; `scaffold doctor` verifies git, SOPS, age key/recipient, kustomize, GitOps repo path, branch, remote, credentials, app repo context when needed, and dirty worktrees before writes.
- **Command model:** `init`, `update`, `diff` or dry-run, `doctor`, and `version` are explicit. Bare `scaffold` may remain an init alias only.
- **Dockerfile-first detection:** Dockerfile presence is the primary containerization signal. Framework/T3 detection is only a template/profile hint. Existing Dockerfiles are preserved byte-for-byte.
- **Dockerfile generation:** Generation is opt-in, previewable, and never overwrites an existing Dockerfile without a future explicit replace feature.
- **Existing-service update:** Update mode mutates only requested fields under `apps/<slug>/`; it must preserve unrelated YAML fields, custom resources, PVCs, service-specific shapes, and absent Service/Ingress resources.
- **Non-secret env vars:** Upserts are deterministic, validate Kubernetes env var names, produce no duplicate entries, warn on likely-sensitive names, and update rollout annotations when pod env changes.
- **Encrypted secrets:** Secret inputs should prefer hidden prompt, stdin, or file over inline command values. Reports and diffs show key-level actions only. Plaintext files must never be staged or left in the GitOps worktree.
- **SOPS correctness:** New or updated secret files use the GitOps repo `.sops.yaml` rule and expected age recipient; decryptability is verified before commit.
- **Kustomization references:** Committed encrypted secret files must align with the existing Argo CMP/Kustomize convention, including referencing decrypted filenames where required.
- **GitOps commit flow:** Mutations follow plan -> apply files -> validate -> stage allowlisted files -> commit -> push. A no-op second run exits cleanly with no commit.
- **Validation:** Required checks include YAML parse, kustomize render, SOPS/decrypt simulation for secret changes, plaintext-secret scan, object-set comparison to catch accidental deletes, and optional Kubernetes dry-run when available.
- **Reporting:** Success output includes service slug, GitOps path, changed files, env keys changed, secret key names changed without values, validation status, commit SHA, and rollback hint.
- **Deferrals:** Defer `adopt`, web UI, PR workflow, Dockerfile lint/refactor systems, database provisioning, public exposure changes bundled with env updates, and replacement of SOPS with another secret backend.

## Sources/Inputs

Synthesized from:

- `.planning/research/STACK.md` - stack additions, dependency choices, versions, and technologies to avoid.
- `.planning/research/FEATURES.md` - table-stakes features, differentiators, anti-features, UX recommendations, and MVP ordering.
- `.planning/research/ARCHITECTURE.md` - component boundaries, data flows, service loader/patcher design, and build order.
- `.planning/research/PITFALLS.md` - critical security, GitOps, SOPS, Kubernetes, and operator workflow failure modes.

Primary local context referenced by the research includes `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, existing `scaffold/internal/*` packages, `.local/gitops-homelab/apps/fintrack/*`, `.local/gitops-homelab/.sops.yaml`, Argo CD ApplicationSet configuration, and `scripts/scaffold-verify.sh`.

External documentation referenced across the research includes official Cobra, Go, Dockerfile, Kubernetes ConfigMap/Secret/env, Kustomize, SOPS, Argo CD, and kyaml documentation. Detailed citations remain in the individual research files.

---
*Research completed: 2026-07-12*
*Ready for roadmap: yes*
