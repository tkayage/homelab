---
phase: 06-build-pipeline-and-project-scaffolding
plan: 02
subsystem: scaffolder
tags: [go, tdd, slug, detection, input-validation, security, next-t3]
status: complete
dependency_graph:
  requires:
    - "Go module github.com/tkayage/homelab/scaffold (from 06-01)"
  provides:
    - "scaffold/internal/slug — Derive + Validate (regex ^[a-z][a-z0-9-]{1,30}$)"
    - "scaffold/internal/detect — Detect returning Result{Kind, Router, Port, HasDockerfile, Warnings}"
    - "detect testdata fixtures (t3-app, t3-pages, nont3-ok, nont3-nouser, nont3-missing)"
  affects:
    - "06-07 orchestrator (imports slug + detect to derive the canonical slug and choose T3 vs non-T3 paths)"
    - "06-03/06-05 template + gitops plans (consume Kind/Router/Port to pick Dockerfile, health route, probe type)"
tech_stack:
  added: []
  patterns:
    - "pure, side-effect-free logic packages under scaffold/internal (no filesystem writes, no exec)"
    - "compiled package-level regexp for slug validation as the single injection guard"
    - "tolerant line-based, case-insensitive Dockerfile directive parsing (EXPOSE/USER)"
    - "read-only detection — SCAF-06 hard rule, an existing Dockerfile is never overwritten"
key_files:
  created:
    - "scaffold/internal/slug/slug.go"
    - "scaffold/internal/slug/slug_test.go"
    - "scaffold/internal/detect/detect.go"
    - "scaffold/internal/detect/detect_test.go"
    - "scaffold/internal/detect/testdata/t3-app/package.json"
    - "scaffold/internal/detect/testdata/t3-app/next.config.js"
    - "scaffold/internal/detect/testdata/t3-app/app/.keep"
    - "scaffold/internal/detect/testdata/t3-pages/package.json"
    - "scaffold/internal/detect/testdata/t3-pages/pages/.keep"
    - "scaffold/internal/detect/testdata/nont3-ok/Dockerfile"
    - "scaffold/internal/detect/testdata/nont3-nouser/Dockerfile"
    - "scaffold/internal/detect/testdata/nont3-missing/.keep"
  modified: []
decisions:
  - "Slug regex ^[a-z][a-z0-9-]{1,30}$ = total length 2-31; enforced identically for derived slugs and --slug overrides"
  - "Missing-Dockerfile non-T3 returns BOTH a NonT3 Result (HasDockerfile=false) AND a non-nil error, so the orchestrator gets a typed result plus a clear failure message"
  - "Router defaults to app when neither app/ nor pages/ is present (Assumption A5)"
  - "Port precedence: --port override > parsed EXPOSE > default 3000"
metrics:
  duration: "~12m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 12
  commits: 4
requirements: [SCAF-01, SCAF-06]
---

# Phase 06 Plan 02: Slug + Detection Pure-Logic Packages Summary

Built the two deterministic input→output packages the scaffolder stands on — `slug` (canonical identifier derivation + strict regex validation, the path-injection guard for T-06-07) and `detect` (T3-vs-non-T3 classification, read-only Dockerfile inspection, Next.js router detection for SCAF-06) — TDD-first, both with full unit coverage and green tests.

## What Was Built

**Task 1 — `internal/slug` (SCAF-01, threat T-06-07).** RED→GREEN.
- `Validate(string) error`: rejects anything not matching a compiled package-level `^[a-z][a-z0-9-]{1,30}$` (uppercase, leading digit, underscore, single char, 32+ chars, empty, leading/trailing hyphen all rejected; length window is 2–31). This is the single injection guard — every derived slug and every operator `--slug` override runs through it before any consumer writes a path, image ref, or manifest.
- `Derive(dir string) (string, error)`: lowercases `filepath.Base(dir)`, replaces `[^a-z0-9-]` with `-`, trims leading/trailing `-`, then `Validate`s. On failure it returns `""` plus `cannot derive valid slug from %q; pass --slug` — it never emits an invalid slug. A test asserts every successful Derive result itself passes Validate.
- Package is side-effect free: no filesystem writes, no exec.

**Task 2 — `internal/detect` (SCAF-06, threat T-06-09).** RED→GREEN.
- `Detect(dir string, portOverride int, dockerfilePath string) (Result, error)` where `Result{Kind (T3|NonT3), Router (app|pages), Port, HasDockerfile, Warnings}`.
- T3 rule: `package.json` parses and declares `next` in `dependencies` or `devDependencies`. Router rule: `app/` → app, else `pages/` → pages, else default app (A5).
- Non-T3 rule: locate a Dockerfile at `dir` root or the `--dockerfile` path; tolerant, case-insensitive, line-based parse of the first `EXPOSE` (handles `8080/tcp`); scan for a non-root `USER` and warn if absent. Missing Dockerfile → `NonT3` result with `HasDockerfile=false` **and** a clear non-nil error (non-T3 must supply its own image config).
- Port precedence: `--port` override > parsed `EXPOSE` > default 3000.
- Detection is strictly read-only — a dedicated test reads both fixture Dockerfiles before and after `Detect` and asserts byte-identical content (SCAF-06: never overwrite an existing Dockerfile).
- Fixtures: `t3-app` (next dep + `app/`), `t3-pages` (next devDep + `pages/`), `nont3-ok` (EXPOSE 8080 + `USER app`), `nont3-nouser` (EXPOSE 5000, no USER), `nont3-missing` (empty).

## Verification Results

- `go test -C scaffold ./internal/slug/...` → ok.
- `go test -C scaffold ./internal/detect/...` → ok.
- `go test -C scaffold ./...` → all packages ok (slug, detect; cmd/scaffold has no tests).
- `go vet -C scaffold ./internal/slug/... ./internal/detect/...` → clean.
- `go build -C scaffold ./...` → BUILD OK.
- `git status --short scaffold/internal/detect/testdata` after the full run → empty (no fixture Dockerfile mutated).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing test fixture] Added a `t3-pages` fixture + router-directory markers.**
- **Found during:** Task 2.
- **Issue:** The behavior spec requires a pages-router case and app/pages directory markers, but `files_modified` listed only `t3-app`'s `package.json`/`next.config.js`. Git also cannot track empty directories, so the `app/` and `pages/` router markers needed a tracked file.
- **Fix:** Created `testdata/t3-pages/{package.json,pages/.keep}` and `testdata/t3-app/app/.keep` so both router branches are covered and the marker dirs are committed.
- **Files modified:** `scaffold/internal/detect/testdata/t3-pages/*`, `scaffold/internal/detect/testdata/t3-app/app/.keep`.
- **Commit:** fdc031a.

### Notes

- The missing-Dockerfile case returns both a typed `Result` (Kind=NonT3, HasDockerfile=false) and a non-nil error, per the plan's "error or a NonT3 result flagged 'no Dockerfile'" — chosen to give the 06-07 orchestrator both the classification and a ready failure message.
- Per the orchestrator's instructions, STATE.md and ROADMAP.md were intentionally **not** updated by this executor. (`.planning/STATE.md` and `.planning/config.json` show as modified in the tree from the init query / prior session — left untouched here.)

## TDD Gate Compliance

Plan `type: tdd`; both tasks followed RED→GREEN with distinct commits:
- Slug: `test(06)` 4c2cd4a (RED, build-fail on undefined symbols) → `feat(06)` e3af65a (GREEN).
- Detect: `test(06)` fdc031a (RED) → `feat(06)` f25dc44 (GREEN).
No REFACTOR commits were needed (implementations were clean on first green). No test passed unexpectedly during RED.

## Threat Model Coverage

- **T-06-07 (Tampering — slug/path injection, high, mitigate):** `slug.Validate` enforces `^[a-z][a-z0-9-]{1,30}$` and is applied to both derived slugs and `--slug` overrides before any write; `Derive` refuses to emit an invalid slug. ✅ Mitigated.
- **T-06-09 (Tampering — non-T3 Dockerfile, medium, mitigate):** `detect.Detect` is read-only; a regression test proves fixture Dockerfiles are byte-unchanged after detection; `--dockerfile`/`--port` are honored, not written. ✅ Mitigated.
- **T-06-10 (DoS — parsing, low, accept):** parsing is line-based over local operator-trusted repo files, no network input. ✅ As accepted.

## Requirements Satisfied

- **SCAF-01:** canonical-slug foundation (`Derive`/`Validate`) implemented and fully tested.
- **SCAF-06:** T3/non-T3 detection, EXPOSE port parse, router detection, non-root USER warning, and never-overwrite guarantee implemented and tested.

## Commits

- `4c2cd4a` test(06): add failing tests for slug derive + strict validation
- `e3af65a` feat(06): implement slug derivation + strict regex validation (SCAF-01, T-06-07)
- `fdc031a` test(06): add failing tests + fixtures for T3/non-T3 detection (SCAF-06)
- `f25dc44` feat(06): implement T3/non-T3 detection with read-only Dockerfile inspection (SCAF-06, T-06-09)

## Self-Check: PASSED

- scaffold/internal/slug/slug.go — FOUND
- scaffold/internal/slug/slug_test.go — FOUND
- scaffold/internal/detect/detect.go — FOUND
- scaffold/internal/detect/detect_test.go — FOUND
- scaffold/internal/detect/testdata/{t3-app,t3-pages,nont3-ok,nont3-nouser,nont3-missing} — FOUND
- commit 4c2cd4a — FOUND
- commit e3af65a — FOUND
- commit fdc031a — FOUND
- commit f25dc44 — FOUND
