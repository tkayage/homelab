---
phase: 06-build-pipeline-and-project-scaffolding
plan: 03
subsystem: scaffolder
tags: [go, embed, text-template, golden-tests, dockerfile, next-t3, health-route, supply-chain]
status: complete
dependency_graph:
  requires:
    - "Go module github.com/tkayage/homelab/scaffold (from 06-01)"
    - "scaffold/internal/detect Result{Kind, Router, Port} (from 06-02) — the orchestrator uses Router to pick app vs pages health route"
  provides:
    - "scaffold/internal/templates — Render(name, data), RenderToFile(name, data, dest), //go:embed all:files"
    - "files/Dockerfile.t3.tmpl — multi-stage Next standalone build, digest-pinned base, non-root uid 1001, {{.Port}} parameterized"
    - "files/health.route.ts.tmpl (App Router) + files/health.page.ts.tmpl (Pages Router) — 200 handlers"
    - "golden fixtures under testdata/ locking rendered output byte-for-byte"
  affects:
    - "06-04 (CI workflow) and 06-05 (gitops manifests) add more .tmpl under files/ and render them through this same Render seam"
    - "06-07 orchestrator selects the health-route template from detect.Router and renders the Dockerfile with the resolved Port"
tech_stack:
  added: []
  patterns:
    - "//go:embed all:files bundles every template into the single static binary (all: prefix so dotfiles are included)"
    - "text/template (NOT html/template) with Option(missingkey=error) so an unset field fails loudly, never emits <no value>"
    - "render() parse+execute core split from Render() so the render contract is unit-testable against inline content without a shipped fixture"
    - "golden-file tests asserting byte-identical renders plus targeted security-property substring assertions"
    - "supply-chain: base image pinned by digest via ARG NODE_IMAGE, not a floating tag"
key_files:
  created:
    - "scaffold/internal/templates/templates.go"
    - "scaffold/internal/templates/templates_test.go"
    - "scaffold/internal/templates/files/.keep"
    - "scaffold/internal/templates/files/Dockerfile.t3.tmpl"
    - "scaffold/internal/templates/files/health.route.ts.tmpl"
    - "scaffold/internal/templates/files/health.page.ts.tmpl"
    - "scaffold/internal/templates/testdata/dockerfile.golden"
    - "scaffold/internal/templates/testdata/health.route.golden"
    - "scaffold/internal/templates/testdata/health.page.golden"
  modified: []
decisions:
  - "Templates live UNDER the package at scaffold/internal/templates/files/ (RESEARCH layout corrected — Go //go:embed cannot reference a parent path)"
  - "node:22-alpine digest resolved at execution time to sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 (cross-checked with `docker buildx imagetools inspect`); pinned via ARG NODE_IMAGE used by all three FROM lines"
  - "Base image pinned once as a global ARG before the first FROM (used only in FROM lines), so all stages share the identical pinned digest"
  - "Container port parameterized as {{.Port}} on both ENV PORT and EXPOSE; health templates are static (no fields), rendered with nil data"
  - "render() core extracted so the missingkey=error contract can be tested with inline template content — no test fixture shipped in the embedded FS"
metrics:
  duration: "~3m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 9
  commits: 3
requirements: [SCAF-02]
---

# Phase 06 Plan 03: Template Subsystem + T3 Dockerfile & Health Routes Summary

Built the shared rendering seam every later build-pipeline plan stands on — `internal/templates` (`//go:embed all:files` + a `text/template` `Render`/`RenderToFile` helper with `missingkey=error`) — and authored the first app-repo build artifacts it serves: the T3/Next standalone Dockerfile (digest-pinned base, non-root uid 1001, `HOSTNAME=0.0.0.0`, parameterized port) and both health-route handlers (App Router + Pages Router), all golden-locked and green.

## What Was Built

**Task 1 — `internal/templates` embed + Render (commit `8df7316`).**
- `//go:embed all:files` binds an `embed.FS`; the `all:` prefix is required so the seed `files/.keep` (a dotfile) is included until real templates land.
- `Render(name string, data any) ([]byte, error)` reads `files/<name>` and parses with **text/template** (never html/template — it would HTML-escape YAML/Dockerfiles). Every parse sets `Option("missingkey=error")` so a template referencing a field absent from `data` fails loudly instead of emitting `<no value>` (threat T-06-12). Supports nested names (e.g. `gitops/deployment.yaml.tmpl`) that 06-04/06-05 will add.
- `RenderToFile(name, data, destPath)` renders then writes mode `0644` (non-secret files; the SOPS pull secret is encrypted separately in 06-05).
- The parse+execute core is split into an unexported `render(name, content, data)` so the render contract is unit-testable against inline template content without shipping a fixture in the embedded binary.
- Tests: resolves an embedded file (`.keep` → empty), errors on an unknown name, and errors on a missing key (with an explicit assertion that `<no value>` never appears).

**Task 2 — T3 Dockerfile + health-route templates, golden-locked (RED `cd4ec1c` → GREEN `0d4f693`).**
- `Dockerfile.t3.tmpl`: three-stage `deps → builder → runner` Next.js `output: 'standalone'` build. Base image **pinned by digest** via `ARG NODE_IMAGE=node:22-alpine@sha256:16e22a...` (resolved and cross-checked at execution time), used by all three `FROM` lines — no floating tag (threat T-06-04). Runner stage creates a system `nextjs` user at **uid 1001** and drops to it with `USER nextjs` (threat T-06-11), sets `NODE_ENV=production`, `NEXT_TELEMETRY_DISABLED=1`, `HOSTNAME=0.0.0.0` (or Next binds localhost and probes fail), and parameterizes the container port `{{.Port}}` on both `ENV PORT` and `EXPOSE`. `CMD ["node", "server.js"]`.
- `health.route.ts.tmpl` (App Router): `export const dynamic = 'force-dynamic'; export function GET()` → `new Response('ok', { status: 200 })`.
- `health.page.ts.tmpl` (Pages Router): default `handler(req, res)` → `res.status(200).send('ok')`. The 06-07 orchestrator picks between the two from `detect.Router`.
- Golden fixtures (`testdata/dockerfile.golden`, `health.route.golden`, `health.page.golden`) assert byte-identical renders; extra assertions verify the digest pin (`@sha256:`), the stage names, `HOSTNAME=0.0.0.0`, `--uid 1001`/`USER nextjs`, `standalone`, `CMD`, and that a non-default port (8080) propagates to both `ENV PORT` and `EXPOSE`.

## Verification Results

- `go test -C scaffold ./internal/templates/...` → ok (7 tests: 3 render-contract + 4 golden/property).
- `go test -C scaffold ./...` → all packages ok (slug, detect, templates; cmd/scaffold has no tests).
- `go vet -C scaffold ./internal/templates/...` → clean.
- `go build -C scaffold ./...` → BUILD OK.
- Verbose run confirms `TestGoldenDockerfileT3`, `TestGoldenDockerfilePortParam`, `TestGoldenHealthRouteApp`, `TestGoldenHealthPagePages` all PASS.
- Post-commit deletion check → none; no untracked files left under the package.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Test completeness] Added a golden + a port-parameterization test beyond the plan's listed fixtures.**
- **Found during:** Task 2.
- **Issue:** The plan's `files_modified` listed goldens only for the Dockerfile and the App Router route, but the behavior spec also requires the Pages Router variant to render a 200 handler, and requires the port to be parameterized. A substring-only check for the Pages route would be weaker than the byte-exact golden used for its sibling.
- **Fix:** Added `testdata/health.page.golden` (byte-exact lock for the Pages Router handler) and `TestGoldenDockerfilePortParam` (asserts port 8080 flows into both `ENV PORT` and `EXPOSE`). No production code changed.
- **Files modified:** `scaffold/internal/templates/testdata/health.page.golden`, `scaffold/internal/templates/templates_test.go`.
- **Commit:** `cd4ec1c` (RED), locked green by `0d4f693`.

### Notes

- **RESEARCH layout correction (as directed by the plan objective):** template files live at `scaffold/internal/templates/files/`, not the `scaffold/templates/` shown in RESEARCH's "Recommended Project Structure" — Go's `//go:embed` cannot use a `..` parent path. 06-04/06-05 must add their `.tmpl` (including the `gitops/` subtree) under this `files/` directory.
- Per the orchestrator's instructions, STATE.md and ROADMAP.md were intentionally **not** updated by this executor.

## TDD Gate Compliance

Task 2 is `tdd="true"` and followed RED → GREEN with distinct commits:
- RED `cd4ec1c` `test(06-03)`: golden fixtures + 4 golden/property tests failing on absent templates (`Render` returns not-found).
- GREEN `0d4f693` `feat(06-03)`: the three templates added; renders match goldens.
No test passed unexpectedly during RED (all four failed on the missing template file). No REFACTOR commit was needed. Task 1 is `type="auto"` (not TDD) and was committed as a single `feat`.

## Threat Model Coverage

- **T-06-04 (Tampering — base image, medium, mitigate):** `node:22-alpine` pinned by digest (`@sha256:16e22a...`) via `ARG NODE_IMAGE`; a test asserts `@sha256:` is present and that no floating `FROM node:22-alpine` tag appears. ✅ Mitigated.
- **T-06-11 (Elevation of Privilege — runtime user, medium, mitigate):** runner stage creates a system user at uid 1001 and runs `USER nextjs`; asserted in the golden test. ✅ Mitigated.
- **T-06-12 (Tampering — missingkey, low, mitigate):** `text/template` with `Option("missingkey=error")`; a test proves a missing key errors and never emits `<no value>`. ✅ Mitigated.

No new security surface beyond the plan's threat register was introduced.

## Requirements Satisfied

- **SCAF-02 (part 1):** the scaffolder can render embedded templates via a shared seam, and the T3 Dockerfile + both health-route variants are proven, secure (digest-pinned, non-root), and golden-locked. The Render seam is ready for 06-04 (CI workflow) and 06-05 (gitops manifests).

## Commits

- `8df7316` feat(06-03): template embed + Render/RenderToFile helper (missingkey=error)
- `cd4ec1c` test(06-03): failing golden tests for T3 Dockerfile + health routes
- `0d4f693` feat(06-03): T3 Dockerfile + health-route templates (SCAF-02)

## Self-Check: PASSED
