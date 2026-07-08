---
phase: 06-build-pipeline-and-project-scaffolding
plan: 07
subsystem: scaffolder
tags: [go, cobra, orchestration, report, end-to-end, gitops, tdd, scaf-01, scaf-05]
status: complete
dependency_graph:
  requires:
    - "scaffold/internal/slug — Derive + Validate (06-02)"
    - "scaffold/internal/detect — Detect{Kind, Router, Port, HasDockerfile, Warnings} (06-02)"
    - "scaffold/internal/templates — Render/RenderToFile + Dockerfile.t3, health.route/page, workflow.deploy (06-03/06-04)"
    - "scaffold/internal/manifests — Render(dir, Data) writing apps/<slug>/ (06-05)"
    - "scaffold/internal/gitops — Publish(cfg, slug, data) clone/encrypt/commit/push (06-06)"
  provides:
    - "scaffold/internal/report — Result struct + Print(w, Result) (SCAF-05 completion report)"
    - "scaffold/internal/scaffolder — Run(Options) (report.Result, error) full end-to-end orchestration (SCAF-01)"
    - "scaffold/cmd/scaffold/main.go — cobra RunE wired to scaffolder.Run (replaces the 06-01 stub); flags --ghcr-org, --dry-run, --gitops-remote"
  affects:
    - "06-08 exercises the live gitops-homelab push with the operator's real read:packages token + GITOPS_PUSH_TOKEN + push preflight"
    - "Phase 8 runs the whole loop against a real GitHub app repo (Actions build->bump->Argo)"
tech_stack:
  added: []
  patterns:
    - "single centralized GHCROrg source (Options.GHCROrg, default tkayage) threaded into BOTH templates (workflow image) AND manifests.Data (Deployment image + kustomization newName) so ghcr.io/<org>/<slug> is byte-identical across CI and gitops (A2, Pitfall 2)"
    - "orchestrator composes pure/side-effecting packages in the RESEARCH 1..6 order; each package keeps its own guardrails (slug.Validate, detect read-only, gitops encrypt+plaintext-guard)"
    - "test/integration seams on Options (GitopsRemote/GitopsWorktree/GitHubEnv/AgeRecipient/AgeKeyFile/SkipPreflight/Pull*) so the end-to-end test runs OFFLINE against a local bare gitops origin with a throwaway age keypair + dummy token"
    - "report as a pure formatter: Print writes a deterministic printf-status block to an io.Writer, no cluster/network calls (health reporting best-effort)"
    - "--dry-run renders app-repo files but skips gitops.Publish entirely (report notes nothing published)"
    - "gitops commit sha read back via git rev-parse --short HEAD on the resolved worktree for the SCAF-05 report"
key_files:
  created:
    - "scaffold/internal/report/report.go"
    - "scaffold/internal/report/report_test.go"
    - "scaffold/internal/scaffolder/scaffolder.go"
    - "scaffold/internal/scaffolder/scaffolder_test.go"
  modified:
    - "scaffold/cmd/scaffold/main.go"
decisions:
  - "GHCROrg centralized on Options and threaded into both the workflow template data and manifests.Data (W2 FIX) — a --ghcr-org flag overrides the tkayage default in one place; the image path can never diverge between CI and manifests"
  - "--dry-run skips gitops.Publish completely (no clone/encrypt/commit/push); the offline end-to-end test does NOT use dry-run — it points --gitops-remote at a local bare repo and injects a throwaway age key + dummy github.env + SkipPreflight via Options seams"
  - "Port precedence delegated to detect.Detect (override > EXPOSE > 3000); the resolved det.Port flows into the Dockerfile, manifests, and report so all three agree; the --port flag default is now 0 (was 3000) so an unset flag lets EXPOSE win for non-T3"
  - "Health-route path chosen from detect.Router (or the --router override): App Router -> app/api/health/route.ts, Pages Router -> pages/api/health.ts; health templates render with nil data (they are static)"
  - "next.config output:'standalone' is not injected; if it cannot be confirmed the scaffolder emits a clear warning (RESEARCH: assert-or-instruct) rather than editing the operator's config"
  - "origin remote is read best-effort for reporting only and discarded — a repo with no remote is not an error (A2 keeps the image path slug-canonical)"
metrics:
  duration: "~18m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 4
  files_modified: 1
  commits: 3
requirements: [SCAF-01, SCAF-05]
---

# Phase 06 Plan 07: End-to-End Scaffold Orchestration + SCAF-05 Report Summary

Composed every wave-2..4 package into the single `scaffold` command and delivered the
operator-facing completion report. `internal/scaffolder.Run` executes the RESEARCH
architecture end-to-end — preflight → repo root → slug → detect → render app-repo files →
`gitops.Publish` → `report.Result` — and cobra's `RunE` now calls it (the 06-01
not-implemented stub is gone). SCAF-01 is true: one invocation scaffolds a containerizable
repo end-to-end, proven against real temp T3 and non-T3 git repos pushed to a local bare
gitops origin. SCAF-05 is delivered: `report.Print` emits the generated files, the gitops
commit + `apps/<slug>/` path, the expected URL, the Argo application name, and a
health-check hint.

## What Was Built

**Task 1 — `internal/report` (SCAF-05), TDD RED→GREEN.**
- `Result{Slug, IsT3, GeneratedFiles, ValidatedDockerfile, GitopsCommit, GitopsPath, URL, ArgoApp, Port, Warnings}` and `Print(w io.Writer, r Result)`, a pure formatter rendering a deterministic printf-status block in the style of `gitops-platform.sh`.
- T3 output lists the generated Dockerfile + health route + workflow and a `httpGet /api/health` probe hint; non-T3 output states the existing Dockerfile was **validated (not overwritten)** and shows the `TCP probe on port <port>` hint. Both carry the gitops commit + path, `https://<slug>.app.kayage.co`, the Argo app name, and `kubectl -n <slug> get deploy,pods`. A `--dry-run` Result (empty `GitopsCommit`) renders `commit: (dry-run — not published)`. Detection warnings are appended when present.
- `report_test.go` captures a `bytes.Buffer` for a T3, a non-T3, and a dry-run Result and asserts the required lines (URL, argo app, gitops commit, `/api/health` vs TCP-probe hint, validated-Dockerfile line).

**Task 2 — `internal/scaffolder` + cobra wiring (SCAF-01 end-to-end).**
- `Run(opts Options) (report.Result, error)` performs: **(1)** preflight (git/sops/kustomize on PATH); **(2)** resolve the app repo root via `git rev-parse --show-toplevel` (origin remote read best-effort for reporting, never fatal — A2); **(3)** `slug.Derive(root)` or validate the `--slug` override; **(4)** `detect.Detect` for Kind/Router/Port/Warnings; **(5)** render app-repo files — **T3**: the standalone Dockerfile (resolved port), the router-correct health route (`app/api/health/route.ts` or `pages/api/health.ts`), and `.github/workflows/deploy.yml`, plus a warning if `next.config` output:'standalone' can't be confirmed; **non-T3**: validate the existing Dockerfile (never written) and render only the workflow; **(6)** `gitops.Publish` to render+encrypt+commit `apps/<slug>/` (skipped under `--dry-run`); **(7)** build the `report.Result` (reads the pushed gitops sha back via `git rev-parse --short HEAD`).
- **W2 FIX:** `Options.GHCROrg` (default `"tkayage"`, flag `--ghcr-org`) is the single centralized GHCR-org source, threaded into BOTH the workflow template data (`{GHCROrg, Slug}`) AND `manifests.Data{GHCROrg}`, so `ghcr.io/<GHCROrg>/<slug>` is byte-identical across the CI image and the gitops Deployment image + kustomization `images.newName`.
- Flags added: `--ghcr-org`, `--dry-run`, `--gitops-remote`. Additional `Options` fields (`GitopsWorktree`, `GitHubEnv`, `AgeRecipient`, `AgeKeyFile`, `SkipPreflight`, `PullUsername/PullPassword`) are integration seams the offline test injects (not exposed as flags; they default to the operator values).
- `main.go` `RunE` parses flags into `scaffolder.Options`, calls `Run`, and `report.Print`s on success.
- `scaffolder_test.go` builds a temp **T3** fixture (package.json with `next`, `app/`, next.config standalone) and a temp **non-T3** fixture (Dockerfile `EXPOSE 8080` + `USER app`) as real git repos, points `--gitops-remote` at a local bare repo, and runs `Run` for each — asserting: the T3 app-repo files exist (Dockerfile is the standalone build, workflow carries `ghcr.io/tkayage/myt3`), the non-T3 Dockerfile is **byte-unchanged**, `apps/<slug>/` is committed to the bare origin with `pull-secret.enc.yaml` and **no** plaintext (real SOPS ciphertext, no token leak), and the `Result` carries the URL + argo app. A third test proves `--dry-run` generates files but leaves `refs/heads/main` unborn on the origin and reports an empty commit.

## Verification Results

- `go test -C scaffold ./internal/report/... ./internal/scaffolder/...` → ok.
- `go test -C scaffold ./...` → all packages ok (slug, detect, templates, manifests, gitops, report, scaffolder).
- `go build -C scaffold ./...` → BUILD OK. `go vet -C scaffold ./...` → clean. `gofmt -l` → clean.
- Manual CLI smoke: built binary, ran `scaffold --dry-run --slug smoke` in a temp T3 repo — printed the full SCAF-05 report and generated `Dockerfile`, `app/api/health/route.ts`, `.github/workflows/deploy.yml`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Fixed the dry-run test's origin-emptiness assertion.**
- **Found during:** Task 2.
- **Issue:** The first draft asserted "no publish" via `git rev-list --count main` with `CombinedOutput()`, which folds git's stderr (`fatal: ambiguous argument 'main'` for an unborn branch) into stdout — the check compared that fatal message instead of a count and failed.
- **Fix:** Replaced with `git show-ref --verify --quiet refs/heads/main`, which exits non-zero exactly when `main` is unborn — the precise "nothing was pushed" signal.
- **Files modified:** `scaffold/internal/scaffolder/scaffolder_test.go`.
- **Commit:** 3453a84 (folded into the Task 2 feat commit; the fix was made before the first commit of that file).

### Notes

- The `--port` flag default changed from `3000` (06-01 skeleton) to `0` so an unset flag lets a non-T3 Dockerfile's `EXPOSE` win via `detect`'s override>EXPOSE>3000 precedence; T3 still defaults to 3000 through `detect`.
- Per the orchestrator's instructions, STATE.md and ROADMAP.md were intentionally **not** updated by this executor.

## TDD Gate Compliance

Task 1 is `tdd="true"` and followed RED → GREEN with distinct commits:
- RED `8cb3a9d` `test(06-07)`: report tests fail to compile (undefined `Result`/`Print`).
- GREEN `d063624` `feat(06-07)`: `report.go` added; tests pass.
No test passed unexpectedly during RED (build failure on undefined symbols). No REFACTOR commit was needed. Task 2 is `type="auto"` (not TDD) and was committed as a single `feat` with its test.

## Threat Model Coverage

- **T-06-07 (Tampering — slug → paths, high, mitigate):** `Run` calls `slug.Derive`/`slug.Validate` before any write; the `--slug` override runs through the identical `Validate`. Composed from 06-02. ✅ Mitigated.
- **T-06-06 (Information Disclosure — end-to-end plaintext secret, high, mitigate):** `Run` composes `gitops.Publish`, which SOPS-encrypts and hard-guards against staging plaintext; the end-to-end test asserts only `pull-secret.enc.yaml` is committed to the origin (real SOPS ciphertext, no token leak) and the plaintext never reaches it. ✅ Mitigated.
- **T-06-18 (Tampering — non-T3 Dockerfile overwrite, medium, mitigate):** the non-T3 path renders only the workflow; the test reads the fixture Dockerfile before and after `Run` and asserts byte-identical content. ✅ Mitigated.

No new security surface beyond the plan's threat register was introduced.

## Known Stubs

The pull-secret credential fields (`Options.PullUsername/PullPassword` → `manifests.Data.Pull*`) carry **dummy** values in tests. This is not a rendering stub: the encryption mechanism and guardrails are complete (06-06); the real classic `read:packages` token is operator-provided and exercised against the live gitops-homelab in **06-08**. The end-to-end gitops publish here is proven fully against a local bare origin with a throwaway age keypair.

## Requirements Satisfied

- **SCAF-01 (scaffold any containerizable project with one command):** `scaffolder.Run` composes preflight→slug→detect→render→publish→report and is wired to cobra; proven end-to-end against real T3 and non-T3 temp repos with a local gitops origin. The live push + operator tokens are 06-08.
- **SCAF-05 (report created resources, deployment status, expected URL):** `report.Print` emits generated files, gitops commit + `apps/<slug>/` path, `https://<slug>.app.kayage.co`, the Argo app name, and a `kubectl` health-check hint (best-effort health since the dev box may lack cluster access).

## Commits

- `8cb3a9d` test(06-07): failing tests for SCAF-05 completion report
- `d063624` feat(06-07): SCAF-05 completion report (report.Print)
- `3453a84` feat(06-07): orchestrate full scaffold + wire cobra (SCAF-01 end-to-end)

## Self-Check: PASSED
