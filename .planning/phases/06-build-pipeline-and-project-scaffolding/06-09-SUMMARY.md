---
phase: 06-build-pipeline-and-project-scaffolding
plan: 09
subsystem: scaffolder
tags: [security, ghcr, gitops, sops, github-actions, gap-closure]
status: complete
dependency_graph:
  requires:
    - "06-VERIFICATION.md — three blocker gaps found after Phase 6 review"
    - "06-REVIEW.md — CR-01 empty pull token, CR-02 plaintext secret lifetime, CR-03 false-success retry loop"
  provides:
    - "Operator-safe GHCR pull token input via --pull-token-file or GHCR_PULL_TOKEN"
    - "Fail-closed publish path when no pull token is resolved"
    - "0600 plaintext pull-secret.yaml plus cleanup on all publish return paths"
    - "Generated workflow retry loop that exits nonzero after exhausted GitOps push retries"
  affects:
    - "Phase 8 validation app can depend on the Phase 6 scaffolder contract for live push -> GHCR -> GitOps -> Argo proof"
tech_stack:
  added: []
  patterns:
    - "Real secrets enter through env/file, not argv; hidden --pull-password remains only for dummy offline fixtures"
    - "Transient plaintext secret files use RenderToFileMode(..., 0600) and best-effort deferred cleanup"
    - "GitHub Actions retry loops track success explicitly instead of relying on break/errexit semantics"
key_files:
  created: []
  modified:
    - "scaffold/cmd/scaffold/main.go"
    - "scaffold/internal/scaffolder/scaffolder.go"
    - "scaffold/internal/scaffolder/scaffolder_test.go"
    - "scaffold/internal/gitops/gitops.go"
    - "scaffold/internal/gitops/gitops_test.go"
    - "scaffold/internal/manifests/manifests.go"
    - "scaffold/internal/manifests/manifests_test.go"
    - "scaffold/internal/templates/templates.go"
    - "scaffold/internal/templates/files/workflow.deploy.yml.tmpl"
    - "scaffold/internal/templates/testdata/workflow.golden"
    - "scaffold/internal/templates/workflow_test.go"
decisions:
  - "Use --pull-token-file and GHCR_PULL_TOKEN as the real operator token mechanisms; keep --pull-password hidden and dummy-only for offline verification fixtures."
  - "Close only the three verified blocker gaps; broader review warnings such as kustomize install pinning and report polish remain outside this gap plan."
metrics:
  duration: "~20m"
  completed: 2026-07-09
  tasks_completed: 4
  files_created: 1
  files_modified: 13
  commits: 2
requirements: [SCAF-04, GITOPS-04]
coverage:
  - id: SCAF-04-PULL-SECRET-TOKEN
    description: "Real non-dry-run publish refuses to proceed without a resolved GHCR pull token and supports safe env/file token input."
    requirement: "SCAF-04"
    verification:
      - kind: test
        ref: "go test -C scaffold ./... (TestRunNonDryRunRequiresPullToken, TestRunUsesPullTokenFile)"
        status: pass
    human_judgment: false
  - id: SCAF-04-PLAINTEXT-SECRET-LIFETIME
    description: "Plaintext pull-secret.yaml is mode 0600 and removed even when SOPS encryption fails."
    requirement: "SCAF-04"
    verification:
      - kind: test
        ref: "go test -C scaffold ./... (TestPullSecretFileModeIsRestrictive, TestPublishCleansPlaintextSecretOnEncryptionFailure)"
        status: pass
    human_judgment: false
  - id: GITOPS-04-PUSH-RETRY-FALSE-SUCCESS
    description: "Generated GitOps push retry loop tracks success and exits 1 after exhausted retries."
    requirement: "GITOPS-04"
    verification:
      - kind: test
        ref: "go test -C scaffold ./... (TestWorkflowStructuralInvariants)"
        status: pass
      - kind: shell
        ref: "bash --noprofile --norc -e -o pipefail retry-loop reproduction exits 1"
        status: pass
    human_judgment: false
---

# Phase 06 Plan 09: Scaffolder Gap Closure Summary

Closed the three Phase 6 blocker gaps found during verification: empty private GHCR pull credentials in real runs, unsafe plaintext pull-secret lifetime, and a GitHub Actions retry loop that could report success without pushing the GitOps bump.

## Accomplishments

- Added regression tests for non-dry-run empty-token refusal, safe token-file input, restrictive pull-secret mode, SOPS-failure cleanup, and workflow retry-loop failure invariants.
- Added operator-safe GHCR pull token input through `--pull-token-file` and `GHCR_PULL_TOKEN`.
- Kept hidden `--pull-password` as a dummy/offline seam only; non-dummy use now errors and points operators to env/file input.
- Changed `pull-secret.yaml` rendering to mode `0600`.
- Added best-effort cleanup of plaintext `pull-secret.yaml` before render and on every publish return path.
- Replaced the generated GitHub Actions retry loop with an explicit `pushed` flag and exhausted-retry `exit 1`.

## Task Commits

1. **Task 1: Lock in failing tests for the three verification blockers** — `b0d976b` (`test`)
2. **Tasks 2-3: Credential/secret lifecycle fixes and retry-loop fix** — `dfe319e` (`fix`)

## Verification Results

- `go test -C scaffold ./...` — PASS
- `bash scripts/scaffold-verify.sh all` — PASS
- Retry-loop reproduction under `bash --noprofile --norc -e -o pipefail` — PASS: all failed attempts exit nonzero
- Secret lifecycle proof — PASS via Go tests:
  - `TestPullSecretFileModeIsRestrictive`
  - `TestPublishCleansPlaintextSecretOnEncryptionFailure`
  - `TestRunNonDryRunRequiresPullToken`
  - `TestRunUsesPullTokenFile`

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact:** none.

## Issues Encountered

- The plan's verification command referenced the old `gsd-core/scripts/gsd-tools.cjs` path. The installed tool is at `~/.codex/gsd-core/bin/gsd-tools.cjs`; verification used the installed path.

## Threat Model Coverage

- **T-06-20 (GHCR pull token argv exposure):** mitigated by env/file real-token paths and dummy-only hidden flag.
- **T-06-21 (empty private-image pull secret):** mitigated by fail-closed non-dry-run token validation.
- **T-06-22 (plaintext pull-secret.yaml):** mitigated by 0600 mode and cleanup on success/failure.
- **T-06-23 (GitOps image bump push):** mitigated by explicit exhausted-retry failure.

## Next Phase Readiness

Phase 6 is safe for Phase 8 to depend on. The live push -> GHCR image -> GitOps bump -> Argo deploy proof remains intentionally deferred to the Phase 8 validation app, but the scaffolder contract no longer has known production-path blockers.

## Self-Check: PASSED
