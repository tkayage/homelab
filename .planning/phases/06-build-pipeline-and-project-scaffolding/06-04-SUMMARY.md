---
phase: 06-build-pipeline-and-project-scaffolding
plan: 04
subsystem: scaffolder
tags: [go, github-actions, ghcr, gitops, kustomize, golden-tests, actionlint, supply-chain]
status: complete
dependency_graph:
  requires:
    - "scaffold/internal/templates Render(name, data) + //go:embed all:files (from 06-03) — the workflow template renders through this seam"
    - "text/template missingkey=error contract (from 06-03) — {{.Slug}} and {{.GHCROrg}} must both be supplied or render fails loudly"
  provides:
    - "files/workflow.deploy.yml.tmpl — two-job build→bump GitHub Actions workflow (GITOPS-03 + GITOPS-04)"
    - "workflow_test.go + testdata/workflow.golden — golden lock + actionlint + structural-invariant validation of the rendered workflow"
    - "CI secret contract: GITOPS_PUSH_TOKEN (fine-grained PAT, Contents:write on gitops-homelab only); GITHUB_TOKEN (packages:write) for GHCR"
  affects:
    - "06-05 (gitops manifests) — the kustomize image key ghcr.io/<org>/<slug> must be byte-identical to the Deployment image string this workflow bumps (Pitfall 2)"
    - "06-07 (orchestrator) — supplies {{.Slug}} + {{.GHCROrg}} (default tkayage) when rendering this template into .github/workflows/deploy.yml"
    - "06-08 (operator checkpoint) — operator must create the GITOPS_PUSH_TOKEN Actions secret this workflow consumes"
    - "Phase 8 — live push→build→bump E2E (needs a real GitHub app repo with Actions enabled)"
tech_stack:
  added: []
  patterns:
    - "GitHub Actions expressions embedded in a Go template: ${{\"{{ github.ref }}\"}} escaping so text/template passes ${{ ... }} through literally while still substituting {{.Slug}}/{{.GHCROrg}}"
    - "single short-SHA source: vars step computes ${GITHUB_SHA::7} once -> job output; both the image tag (type=raw,value=sha-<short>) and the gitops pin reuse it byte-identically (Pitfall 5)"
    - "supply-chain: every third-party action pinned to a full 40-hex commit SHA with a trailing # vX.Y.Z comment (T-06-03); test enforces the pin with a regex"
    - "actionlint-in-test: render to a temp .github/workflows/deploy.yml and run actionlint as the schema/expression/shellcheck gate short of a live Actions run"
key_files:
  created:
    - "scaffold/internal/templates/files/workflow.deploy.yml.tmpl"
    - "scaffold/internal/templates/workflow_test.go"
    - "scaffold/internal/templates/testdata/workflow.golden"
  modified: []
decisions:
  - "Image tag driven by type=raw,value=sha-${{ steps.vars.outputs.short_sha }} (NOT metadata-action type=sha,format=short) so the pushed tag is byte-identical to the string the bump job pins — the faithful Pitfall 5 fix; the RESEARCH §3 example's independent format=short derivation is exactly the divergence Pitfall 5 warns against"
  - "Action SHAs resolved at execution time via the GitHub refs API: checkout v4.2.2 11bd719, setup-buildx v3.11.1 e468171, login v3.6.0 5e57cd1, metadata v5.9.0 318604b, build-push v6.18.0 2634353"
  - "kustomize v5.4.3 installed via the pinned official install_kustomize.sh (matches RESEARCH §3); bump runs kustomize edit set image in working-directory: apps/<slug>"
  - "Top-level permissions minimized to contents:read + packages:write; the build job pushes to GHCR with the built-in GITHUB_TOKEN, the bump job pushes to gitops-homelab with the separate fine-grained GITOPS_PUSH_TOKEN (least privilege, T-06-01)"
metrics:
  duration: "~3m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 3
  commits: 2
requirements: [GITOPS-03, GITOPS-04, SCAF-02]
---

# Phase 06 Plan 04: Generated Deploy Workflow (build → bump) Summary

Authored the generated GitHub Actions workflow that is the heart of the promotion loop: on push to `main` it builds and pushes a private, SHA-tagged GHCR image and then bumps the `gitops-homelab` image reference so Argo CD auto-syncs the new digest — a single two-job `build`→`bump` template, actionlint-validated and golden-locked, with least-privilege tokens and every action pinned to a full commit SHA.

## What Was Built

**Task 1 — build job (commit `8fe636e`).**
- `files/workflow.deploy.yml.tmpl` created under the 06-03 embed root (`internal/templates/files/`), rendered through the existing `Render` seam. Trigger `on: push: branches: [main]`; a `concurrency` group on `github.ref`; top-level `permissions: {contents: read, packages: write}` (least privilege, T-06-02).
- The `build` job: checkout (pinned) → a `vars` step computing `short_sha=${GITHUB_SHA::7}` exposed as the **job output** `short_sha` → `docker/setup-buildx-action` → `docker/login-action` to `ghcr.io` with `github.actor` + `secrets.GITHUB_TOKEN` (the action masks the token, T-06-02) → `docker/metadata-action` with `images: ghcr.io/{{.GHCROrg}}/{{.Slug}}` and tags `type=raw,value=sha-<short_sha>` + `type=raw,value=latest,enable={{is_default_branch}}` → `docker/build-push-action` (`push: true`, metadata tags/labels, gha cache).
- Every action pinned to a **full 40-hex commit SHA** with a trailing `# vX.Y.Z` comment (T-06-03), resolved at execution time.

**Task 2 — bump job + validation (commit `42c5f6d`).**
- Added the `bump` job with `needs: build` (T-06-04 race guard, Pitfall 4). Steps: checkout `{{.GHCROrg}}/gitops-homelab@main` using `secrets.GITOPS_PUSH_TOKEN` (fine-grained PAT, Contents:write only — T-06-01) → install kustomize v5.4.3 via the pinned official script → `working-directory: apps/{{.Slug}}` run `kustomize edit set image ghcr.io/<org>/<slug>=ghcr.io/<org>/<slug>:sha-${{ needs.build.outputs.short_sha }}` (reuses the exact short SHA, Pitfall 5; image key byte-identical to the Deployment string, Pitfall 2) → git config a CI identity, add `kustomization.yaml`, commit (`|| exit 0` when unchanged), and push `main` behind a 3-try `git pull --rebase` loop (two-writer contention, Pitfall 6).
- `workflow_test.go`: renders with a sample slug+org, asserts byte-equality with `testdata/workflow.golden`, runs **actionlint** on the rendered workflow in a temp `.github/workflows/deploy.yml` layout (skips only if actionlint is unexpectedly absent — it is present), and asserts structural invariants (build→bump ordering, `short_sha` output reuse across the tag flow and the kustomize edit, least-privilege permissions, correct token wiring, the rebase-retry loop, and a regex proving every `uses:` is pinned to a 40-hex SHA).

## Verification Results

- `go build -C scaffold ./internal/templates/...` → BUILD OK (Task 1 gate).
- `go test -C scaffold ./internal/templates/...` → ok. Verbose confirms `TestGoldenWorkflow`, `TestWorkflowActionlint` (ran, not skipped), and `TestWorkflowStructuralInvariants` all PASS.
- `actionlint` on the rendered workflow → exit 0, no problems (schema, expression contexts, and shellcheck of every `run:` block clean).
- `go vet -C scaffold ./internal/templates/...` → clean.
- `go test -C scaffold ./...` → all packages ok (slug, detect, templates).
- Self-check: all three created files present; both commits found; no unintended deletions; no stray untracked files under the package.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Correctness] Image tag driven by the single computed short_sha instead of metadata-action's independent `type=sha,format=short`.**
- **Found during:** Task 1, wiring the tag flow.
- **Issue:** The RESEARCH §3 example tags the image via `docker/metadata-action` `type=sha,prefix=sha-,format=short`, which derives the short SHA independently of the `${GITHUB_SHA::7}` value the bump job pins. That independent derivation is exactly the byte-identical-reuse hazard Pitfall 5 (and the plan objective: "reuse the exact short-SHA string") warns against — the two 7-char strings happen to match today but are not guaranteed to.
- **Fix:** The metadata tag uses `type=raw,value=sha-${{ steps.vars.outputs.short_sha }}`, so the pushed tag and the gitops pin both derive from the identical `short_sha` job output. This is the faithful implementation of the plan's load-bearing requirement, not a scope change. `latest` on the default branch is preserved via a second `type=raw` tag.
- **Files modified:** `scaffold/internal/templates/files/workflow.deploy.yml.tmpl`.
- **Commit:** `8fe636e`.

### Notes

- Per the orchestrator's instructions, STATE.md and ROADMAP.md were intentionally **not** updated by this executor (they are shown modified in the working tree by the orchestrator's own bookkeeping).
- Live push→build→bump E2E is intentionally deferred to Phase 8 (needs a real GitHub app repo with Actions). Phase 6 proves the workflow is valid and correctly structured in isolation via actionlint + golden + structural tests, as the plan scopes.

## Threat Model Coverage

- **T-06-01 (EoP — GITOPS_PUSH_TOKEN scope, high, mitigate):** the cross-repo bump uses a fine-grained PAT (`secrets.GITOPS_PUSH_TOKEN`) scoped to `gitops-homelab` Contents:write only, never for GHCR reads; GHCR login uses the built-in `GITHUB_TOKEN`. Asserted in `TestWorkflowStructuralInvariants`. ✅ Mitigated.
- **T-06-02 (Info Disclosure — token handling, high, mitigate):** `docker/login-action` masks the registry token; no `echo`/`run` prints a secret; top-level `permissions:` minimized to `contents: read` + `packages: write` (a test rejects top-level `contents: write`). ✅ Mitigated.
- **T-06-03 (Tampering — third-party actions, high, mitigate):** `actions/checkout` and all `docker/*` actions pinned to full 40-hex commit SHAs with version comments; a regex test fails on any non-SHA `uses:` ref. ✅ Mitigated.
- **T-06-13 (DoS — build→bump race / two-writer push, medium, mitigate):** `bump` declares `needs: build`; the exact `short_sha` job output is reused byte-identically; the gitops push runs behind a `git pull --rebase` retry loop. Asserted in the structural test. ✅ Mitigated.

No new security surface beyond the plan's threat register was introduced.

## Requirements Satisfied

- **GITOPS-03:** on push to `main` the workflow builds and pushes a private, versioned GHCR image (`ghcr.io/<org>/<slug>:sha-<short>` + `latest`) using `GITHUB_TOKEN` packages:write.
- **GITOPS-04:** CI advances the gitops image reference without manual cluster commands — `bump` checks out `gitops-homelab`, runs `kustomize edit set image` in `apps/<slug>/`, and commits+pushes `main` for Argo to auto-sync.
- **SCAF-02 (workflow half):** the scaffolder generates a valid, secure GitHub Actions workflow, golden-locked and actionlint-validated. (The Dockerfile half landed in 06-03; the non-T3 detect/validate path is elsewhere in the phase.)

## Commits

- `8fe636e` feat(06-04): deploy workflow build job — SHA-pinned GHCR push (GITOPS-03)
- `42c5f6d` feat(06-04): bump job + actionlint golden test — gitops image bump (GITOPS-04)

## Self-Check: PASSED
