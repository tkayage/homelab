---
phase: 6
slug: build-pipeline-and-project-scaffolding
status: draft
nyquist_compliant: false
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
| 06-…    | …    | …    | …           | …         | `…`               | ⬜ pending |

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
