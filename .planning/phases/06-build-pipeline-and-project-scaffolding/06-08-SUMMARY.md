---
phase: 06-build-pipeline-and-project-scaffolding
plan: 08
subsystem: scaffolder
tags: [bash, fixtures, offline-e2e, sops, kustomize, actionlint, kubectl-dry-run, ghcr, tokens, scaf-06]
status: complete
dependency_graph:
  requires:
    - "scaffold/cmd/scaffold + internal/scaffolder — full end-to-end Run wired to cobra (06-07)"
    - "scaffold/internal/gitops — Publish with SOPS encryption + plaintext guard (06-06)"
    - "dev-box tooling: sops, kustomize, actionlint on PATH (06-01)"
  provides:
    - "scripts/scaffold-verify.sh — repeatable offline validator (all|t3|nont3): build → scaffold → SOPS round-trip → kustomize build → actionlint → kubectl dry-run"
    - "tests/fixtures/scaffold/t3-fixture — minimal Next standalone T3 project (App Router marker)"
    - "tests/fixtures/scaffold/nont3-fixture — own Dockerfile (EXPOSE 8080 + non-root USER), the SCAF-06 never-overwrite contract fixture"
    - "Operator CI/GitOps credential: ONE classic PAT (repo + read:packages) covering gitops push and GHCR pull (accepted-risk deviation on T-06-01)"
  affects:
    - "Phase 8 validation app runs the live push→build→GHCR→bump→Argo loop using the operator token; store it as the GITOPS_PUSH_TOKEN Actions secret on the app repo"
tech_stack:
  added: []
  patterns:
    - "scripts/*-platform.sh convention carried to scaffold-verify.sh: shebang, set -euo pipefail, ROOT resolution, die/need helpers, KUBECONFIG default .local/kubeconfig-k3s-01, case dispatch"
    - "offline E2E harness: scratch app repo + LOCAL bare gitops origin + throwaway age keypair + clearly-dummy pull token — no GitHub, no operator key, no real secret ever written"
    - "scaffolder.Options offline seams exposed as HIDDEN cobra flags (--skip-preflight, --github-env, --age-recipient, --age-key-file, --gitops-worktree, --pull-username, --pull-password) so the built binary can publish offline without polluting operator --help"
key_files:
  created:
    - "scripts/scaffold-verify.sh"
    - "tests/fixtures/scaffold/t3-fixture/package.json"
    - "tests/fixtures/scaffold/t3-fixture/next.config.js"
    - "tests/fixtures/scaffold/t3-fixture/app/page.tsx"
    - "tests/fixtures/scaffold/nont3-fixture/Dockerfile"
    - "tests/fixtures/scaffold/nont3-fixture/server.js"
    - "tests/fixtures/scaffold/README.md"
  modified:
    - "scaffold/cmd/scaffold/main.go"
decisions:
  - "Operator chose ONE classic PAT (repo + read:packages) for both the gitops bump push and the GHCR pull secret, instead of the planned fine-grained GITOPS_PUSH_TOKEN + classic read:packages pair — recorded as an accepted-risk deviation on threat T-06-01 (see Deviations)"
  - "Offline seams exposed as hidden flags on the built binary rather than a test-only build tag, so scaffold-verify.sh exercises the real shipped binary end-to-end"
  - "kubectl validation prefers --dry-run=server when the cluster is reachable via KUBECONFIG (it was), falling back to client-side otherwise — the run validated against the live k3s API without mutating anything"
metrics:
  duration: "~2m execution (prior session) + close-out session (re-verify + checkpoint)"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 7
  files_modified: 1
  commits: 1
requirements: [SCAF-06, GITOPS-03, GITOPS-04]
coverage:
  - id: D1
    description: "scripts/scaffold-verify.sh scaffolds the T3 fixture offline: app-repo files generated (Dockerfile + health route + workflow), SOPS round-trip, kustomize build with image pinned, actionlint, kubectl dry-run all pass"
    requirement: "GITOPS-03"
    verification:
      - kind: e2e
        ref: "bash scripts/scaffold-verify.sh all (t3-fixture: PASS)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Non-T3 fixture's own Dockerfile is validated and byte-unchanged after scaffolding (SCAF-06); only the workflow is generated; same offline pipeline passes"
    requirement: "SCAF-06"
    verification:
      - kind: e2e
        ref: "bash scripts/scaffold-verify.sh all (nont3-fixture: PASS, Dockerfile byte-unchanged assertion)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Operator created the CI/GitOps credential (one classic PAT: repo + read:packages), confirmed GHCR package privacy, and reviewed generated action pins (all full commit SHAs)"
    requirement: "GITOPS-04"
    verification: []
    human_judgment: true
    rationale: "Token creation and GHCR visibility live in the operator's GitHub account — not automatable or inspectable from the repo. Approved at the blocking checkpoint on 2026-07-08."
---

# Phase 06 Plan 08: Offline Scaffold Validator + Operator Token Checkpoint Summary

**Repeatable offline validator proving the whole scaffold pipeline (generate → SOPS → kustomize → actionlint → kubectl dry-run) against committed T3 and non-T3 fixtures, plus the operator credential checkpoint — approved with a one-classic-token deviation.**

## Performance

- **Duration:** Task 1 executed in a prior session (interrupted at the Task 2 checkpoint before SUMMARY); this session re-verified Task 1 end-to-end and resolved the checkpoint
- **Completed:** 2026-07-08
- **Tasks:** 2/2
- **Files:** 7 created, 1 modified

## Accomplishments

- `scripts/scaffold-verify.sh` (subcommands `all|t3|nont3`) builds the real scaffolder binary, scaffolds each fixture into a scratch app repo publishing `apps/<slug>/` to a LOCAL bare gitops origin (throwaway age keypair + clearly-dummy pull token), then proves offline: expected app-repo files generated, only SOPS ciphertext committed (no token leak), SOPS round-trip decrypts, `kustomize build` succeeds with the image pinned to `ghcr.io/tkayage/<slug>`, actionlint passes on the generated workflow, and `kubectl --dry-run=server` validates the rendered manifests.
- SCAF-06 demonstrated: the non-T3 fixture's own Dockerfile (EXPOSE 8080 + non-root USER) is validated and **byte-unchanged** after scaffolding — only the workflow is generated.
- Operator checkpoint resolved: CI/GitOps credential created (see deviation), GHCR package privacy confirmed, and all 6 `uses:` entries in the generated workflow verified pinned to full commit SHAs.

## Task Commits

1. **Task 1: Fixture repos + offline scaffold-verify.sh** — `853748c` (feat)
2. **Task 2: Operator token checkpoint** — no repo files (external GitHub account actions); approved 2026-07-08

## Verification Results

Re-run this session (close-out): `bash scripts/scaffold-verify.sh all` →

- t3-fixture: PASS — T3 app-repo files generated; `apps/t3-fixture/` on origin with only SOPS ciphertext; SOPS round-trip + kustomize build OK (image pinned); actionlint OK; kubectl `--dry-run=server` OK.
- nont3-fixture: PASS — Dockerfile byte-unchanged (SCAF-06); only workflow generated; same SOPS/kustomize/actionlint/kubectl checks OK.
- All offline: no GitHub, no live Actions, no real credential written.

## Deviations from Plan

### Accepted-Risk Deviation (operator decision at checkpoint)

**1. [T-06-01 — Elevation of Privilege] One classic PAT instead of two least-privilege tokens**
- **Planned:** fine-grained `GITOPS_PUSH_TOKEN` (Contents:write on tkayage/gitops-homelab only) + separate classic `read:packages` GHCR pull token.
- **Actual:** operator chose ONE classic PAT with `repo + read:packages` scopes covering both duties.
- **Risk accepted:** classic PATs cannot be repo-scoped, so the token embedded (SOPS-encrypted) in gitops pull-secrets and stored as an Actions secret carries write access to ALL owner repos. A CI or cluster compromise escalates to full-account repo write, not just one-repo push / package read. T-06-01's disposition changes from *mitigate* to **accept** by explicit operator decision (offered the two-token path first, declined).
- **Compensating controls still in place:** SOPS encryption of the pull secret (T-06-06/T-06-19), private GHCR package (T-06-05), full-SHA action pins (T-06-03).
- **Recommendation:** rotate to the two-token split before scaffolding apps beyond the Phase 8 validation app.

### Auto-fixed Issues (prior session, recorded in `853748c`)

**2. [Rule 3 — Blocking] Exposed scaffolder.Options offline seams as hidden flags**
- **Found during:** Task 1 (validator needs the built binary to publish offline).
- **Issue:** the shipped binary had no way to run a full publish without GitHub (preflight, github.env, age key, gitops worktree, pull credentials are operator-only paths).
- **Fix:** `scaffold/cmd/scaffold/main.go` exposes the existing `scaffolder.Options` seams as hidden cobra flags (`--skip-preflight`, `--github-env`, `--age-recipient`, `--age-key-file`, `--gitops-worktree`, `--pull-username`, `--pull-password`) — hidden from `--help` so operator UX is unchanged.
- **Files modified:** `scaffold/cmd/scaffold/main.go` (not in the plan's `files_modified` list).
- **Committed in:** `853748c`.

---

**Total deviations:** 1 accepted-risk (operator security decision), 1 auto-fixed (Rule 3 blocking).
**Impact on plan:** validator scope unchanged; security posture consciously traded by the operator and tracked for the milestone audit.

## Issues Encountered

- **Session interruption:** the prior executor session committed Task 1 (`853748c`) and stopped at the blocking human-verify checkpoint without writing this SUMMARY. The safe-resume gate caught the orphaned commit; close-out re-ran the full validator (pass) rather than trusting the commit message, then resumed at the checkpoint.

## Threat Model Coverage

- **T-06-01 (EoP — push token scope, high):** **ACCEPTED RISK** — one classic `repo + read:packages` PAT by operator decision (see Deviations). Not mitigated as planned.
- **T-06-05 (Info Disclosure — GHCR visibility, high):** ✅ Mitigated — operator confirmed package visibility Private at checkpoint; pull path needs only `read:packages` (scope present on the token).
- **T-06-19 (Info Disclosure — dummy vs real token in fixtures, medium):** ✅ Mitigated — validator uses a clearly-dummy token + throwaway age keypair + local bare origin; the run asserts only SOPS ciphertext is committed (no token leak).
- **T-06-03 (Tampering — workflow action pins, high):** ✅ Mitigated — all 6 `uses:` in `workflow.deploy.yml.tmpl` pinned to full commit SHAs (verified at checkpoint).

## User Setup Required

Done at checkpoint: one classic PAT (`repo` + `read:packages`) exists; GHCR privacy confirmed. **Remaining for Phase 8:** store the token as the `GITOPS_PUSH_TOKEN` Actions secret on the validation app repo when it is created (owner-level secret also works).

## Next Phase Readiness

- Phase 6 is provable offline end-to-end: one command scaffolds either project type; generated manifests build and validate; the workflow is lint-clean and SHA-pinned.
- The live push→build→GHCR→bump→Argo loop (GITOPS-03/04 full E2E) is deferred to the Phase 8 validation app per RESEARCH — documented in 06-VALIDATION.md Manual-Only Verifications. The operator credential now exists, so Phase 8 is unblocked.

---
*Phase: 06-build-pipeline-and-project-scaffolding*
*Completed: 2026-07-08*

## Self-Check: PASSED
