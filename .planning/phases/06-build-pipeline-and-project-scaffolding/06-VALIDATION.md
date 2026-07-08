---
phase: 6
slug: build-pipeline-and-project-scaffolding
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-08
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. The
> detailed strategy per requirement lives in `06-RESEARCH.md` (## Validation
> Architecture); the planner lifts per-task verify commands into this map.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `go test` (scaffolder) + shell/bats-style checks (generated artifacts) |
| **Config file** | none — Wave 0 installs `sops` + `kustomize` and sets up the Go module |
| **Quick run command** | `go test ./...` in the scaffolder module |
| **Full suite command** | `go test ./...` + `kustomize build` on a scaffolded fixture app + `sops` round-trip |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `go test ./...` (scaffolder) or the artifact check for that task
- **After every plan wave:** Full suite (unit + `kustomize build` fixture render + sops round-trip)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

*(Filled by the planner from 06-RESEARCH.md ## Validation Architecture — one row per task, mapping each to GITOPS-03/04 and SCAF-01..06.)*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 06-01-T1 | 06-01 | 1 | SCAF-01 (setup) | env/tooling | `command -v sops && command -v kustomize && command -v actionlint && sops --version && kustomize version` | ⬜ pending |
| 06-01-T2 | 06-01 | 1 | SCAF-01 (setup) | build | `go build -C scaffold ./... && go vet -C scaffold ./... && go run -C scaffold ./cmd/scaffold --help` | ⬜ pending |
| 06-02-T1 | 06-02 | 2 | SCAF-01 | unit (TDD) | `go test -C scaffold ./internal/slug/...` | ⬜ pending |
| 06-02-T2 | 06-02 | 2 | SCAF-06 | unit (TDD, fixtures) | `go test -C scaffold ./internal/detect/...` | ⬜ pending |
| 06-03-T1 | 06-03 | 2 | SCAF-02 | unit | `go test -C scaffold ./internal/templates/...` | ⬜ pending |
| 06-03-T2 | 06-03 | 2 | SCAF-02 | golden | `go test -C scaffold ./internal/templates/...` | ⬜ pending |
| 06-04-T1 | 06-04 | 3 | GITOPS-03, SCAF-02 | build | `go build -C scaffold ./internal/templates/...` | ⬜ pending |
| 06-04-T2 | 06-04 | 3 | GITOPS-04, SCAF-02 | golden + actionlint | `go test -C scaffold ./internal/templates/...` | ⬜ pending |
| 06-05-T1 | 06-05 | 3 | SCAF-03, SCAF-04 | golden | `go test -C scaffold ./internal/manifests/...` | ⬜ pending |
| 06-05-T2 | 06-05 | 3 | SCAF-03, SCAF-04 | golden + kustomize build | `go test -C scaffold ./internal/manifests/...` | ⬜ pending |
| 06-06-T1 | 06-06 | 4 | SCAF-03 | integration (bare-repo) | `go test -C scaffold ./internal/gitops/... -run TestGit` | ⬜ pending |
| 06-06-T2 | 06-06 | 4 | SCAF-04 | integration (sops round-trip) | `go test -C scaffold ./internal/gitops/... -run TestSops` | ⬜ pending |
| 06-07-T1 | 06-07 | 5 | SCAF-05 | unit (stdout capture) | `go test -C scaffold ./internal/report/...` | ⬜ pending |
| 06-07-T2 | 06-07 | 5 | SCAF-01 | integration (end-to-end) | `go test -C scaffold ./internal/scaffolder/... && go build -C scaffold ./... && go vet -C scaffold ./...` | ⬜ pending |
| 06-08-T1 | 06-08 | 6 | SCAF-06, GITOPS-03, GITOPS-04 | live-ish offline suite | `bash scripts/scaffold-verify.sh all` | ⬜ pending |
| 06-08-T2 | 06-08 | 6 | GITOPS-04, SCAF-04 | checkpoint:human-verify | operator creates GITOPS_PUSH_TOKEN + classic read:packages token; confirm GHCR private (manual) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Install `sops` and `kustomize` on the dev box (both absent from PATH — research blocker B1)
- [ ] Initialize the Go module for the scaffolder (`go mod init`)
- [ ] Create a minimal fixture app repo to exercise scaffolding + `kustomize build` without needing a live GitHub Actions run (research blocker B2 — full push→build→deploy E2E is proven by the Phase 8 real app)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full push→build→GHCR→bump→Argo deploy loop | GITOPS-03, GITOPS-04 | Needs a real GitHub repo with Actions + two operator-created tokens; deferred to the Phase 8 validation app | Push to a real app's `main`, observe the GHCR image, the gitops bump commit, and Argo sync to `<slug>.app.kayage.co` |
| Operator token creation (GITOPS_PUSH_TOKEN + GHCR read token) | GITOPS-04, SCAF-04 | Requires operator GitHub account access | `checkpoint:human-verify` — operator creates the tokens |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (`sops`, `kustomize`, Go module, fixture repo)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
