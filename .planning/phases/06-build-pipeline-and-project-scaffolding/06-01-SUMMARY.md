---
phase: 06-build-pipeline-and-project-scaffolding
plan: 01
subsystem: scaffolder
tags: [go, cobra, cli, tooling, supply-chain, sops, kustomize, actionlint]
status: complete
dependency_graph:
  requires: []
  provides:
    - "Go module github.com/tkayage/homelab/scaffold (cobra v1.10.2)"
    - "scaffold cobra CLI skeleton with --slug/--port/--dockerfile/--router flags + preflight stub"
    - "sops v3.13.2, kustomize v5.4.3, actionlint v1.7.7 on PATH"
  affects:
    - "all later Phase 6 plans (06-02..06-08) import this module and use these tools"
tech_stack:
  added:
    - "github.com/spf13/cobra v1.10.2 (Go CLI framework)"
    - "github.com/spf13/pflag v1.0.9 (transitive via cobra)"
    - "github.com/inconshreveable/mousetrap v1.1.0 (transitive via cobra)"
  patterns:
    - "isolated Go module under scaffold/ (module path is ASSUMPTION A1)"
    - "cobra root delegates to a scaffold subcommand; root shares the same flagset"
    - "preflight() PATH-check helper = Go analog of gitops-platform.sh need()"
key_files:
  created:
    - "scaffold/go.mod"
    - "scaffold/go.sum"
    - "scaffold/cmd/scaffold/main.go"
    - "scaffold/README.md"
    - "scaffold/.gitignore"
  modified: []
decisions:
  - "Installed dev-box tools to $HOME/.local/bin (/usr/local/bin not writable; no silent sudo)"
  - "Pinned actionlint to v1.7.7 (explicit version, not floating latest) for supply-chain determinism"
  - "Templates will live at scaffold/internal/templates/files/ (NOT scaffold/templates/) — //go:embed cannot use .."
metrics:
  duration: "~15m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 5
  commits: 2
requirements: [SCAF-01]
---

# Phase 06 Plan 01: Wave 0 Groundwork — Dev Tooling + Scaffold Module Skeleton Summary

Installed the three missing dev-box tools (sops v3.13.2, kustomize v5.4.3, actionlint v1.7.7) on PATH and bootstrapped an isolated Go module with a cobra CLI skeleton that parses the four scaffold flags but performs no work yet — unblocking every later Phase 6 plan.

## What Was Built

**Task 1 — Dev-box tooling (supply-chain surface T-06-SC).**
- `sops` v3.13.2: installed by reusing the repo's already-downloaded pinned binary at `.local/downloads/sops-v3.13.2.linux.amd64`, sha256-verified against `154dfe4c…42ef` (matched the checksums file) BEFORE `install -m 0755`.
- `kustomize` v5.4.3: installed via the official `install_kustomize.sh` pinned to `5.4.3` (the same approach the generated CI bump job uses). Real kustomize, not `kubectl kustomize`, so `edit set image` is available for later plans.
- `actionlint` v1.7.7: installed via the official `download-actionlint.bash` pinned to `1.7.7`.
- All three resolve on PATH (installed to `$HOME/.local/bin`, which is already on PATH). No downloaded artifact is committed — `.local/` was already gitignored, and the tools live under `$HOME`, outside the repo.

**Task 2 — scaffold module + cobra skeleton.**
- `go mod init github.com/tkayage/homelab/scaffold` + `go get github.com/spf13/cobra@v1.10.2`; `go.mod`/`go.sum` finalized here (this is the only plan that adds external deps).
- `cmd/scaffold/main.go`: cobra root command that delegates a bare invocation to a `scaffold` subcommand, with persistent flags `--slug` (string), `--port` (int, default 3000), `--dockerfile` (string), `--router` (string enum app|pages). `RunE` prints the parsed flags then returns an explicit `not implemented — scaffolding is wired in plan 06-07` error, so the binary builds and `--help` works but writes nothing.
- `preflight([]string)` helper: Go analog of `gitops-platform.sh` `need()`; asserts `git`/`sops`/`kustomize` resolve on PATH (exposed now so the dependency contract is explicit; called by later plans).
- `README.md`: documents build (`go build -C scaffold -o ../.local/bin/scaffold ./cmd/scaffold`, never commit the binary), run, the required-tools table, and assumptions A1 (module path — repo has NO git remote) and A2 (GHCR org `tkayage`, `ghcr.io/tkayage/<slug>`), noting the org will become a single centralized constant in a later plan.

## Verification Results

- `command -v sops kustomize actionlint` → all resolve; `sops --version`=3.13.2, `kustomize version`=v5.4.3, `actionlint --version`=1.7.7.
- `go build -C scaffold ./...` → BUILD OK.
- `go vet -C scaffold ./...` → VET OK.
- `scaffold --help` → renders the scaffold command + all four flags (--slug/--port/--dockerfile/--router).
- Bare `scaffold --slug demo` → prints parsed flags, returns the not-implemented error, exit 1, writes no files.
- No compiled binary or downloaded tool is staged for commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `/usr/local/bin` not writable → installed to `$HOME/.local/bin`.**
- **Found during:** Task 1.
- **Issue:** The plan prefers `/usr/local/bin` but that dir is not writable and the plan forbids silent sudo.
- **Fix:** Installed all three tools to `$HOME/.local/bin` (the documented fallback, already first on PATH). Reported the path here.
- **Files modified:** none (installs are under $HOME).

**2. [Rule 2 - Missing critical hygiene] Gitignored a stray build artifact.**
- **Found during:** Task 2 verification.
- **Issue:** `go build -C scaffold ./...` (the plan's own verify command) drops a compiled `scaffold/scaffold` binary in-tree, which could be accidentally committed (binaries-in-git anti-pattern the README explicitly warns against).
- **Fix:** Removed the artifact and added `scaffold/.gitignore` ignoring `/scaffold`.
- **Files modified:** `scaffold/.gitignore` (created).
- **Commit:** d68c27d.

### Notes

- **Task 1 produced no repo diff and therefore no per-task commit.** The tool installs land under `$HOME` (outside the repo) and `.local/` was already gitignored (line 13 of the root `.gitignore`), so the plan's "only tracked edit is confirming `.local/` is already gitignored" resolved to a no-op. This is expected per the task's own `<action>` note.
- **actionlint pinned, not floating.** The plan said "install the latest release binary"; I pinned to a specific release (v1.7.7) rather than a floating `latest` so the install is deterministic and recordable (supply-chain intent of T-06-SC).

## Assumptions Recorded (unverified — repo has no git remote)

- **A1:** module path `github.com/tkayage/homelab/scaffold` (baked into `go.mod`; documented in README).
- **A2:** GHCR org `tkayage` → images `ghcr.io/tkayage/<slug>` (documented in README; to be centralized as one constant in a later plan).

## Threat Model Coverage

- **T-06-SC (Tampering, high, mitigate):** sops reused the repo's pinned binary and was sha256-verified before install; kustomize pinned to v5.4.3 via the official script; actionlint pinned to v1.7.7; cobra v1.10.2 is Approved in RESEARCH. No npm/pip/crates package was installed, so no package-legitimacy checkpoint applied. ✅ Mitigated.
- **T-06-08 (Information Disclosure, low, accept):** `.local/` remains gitignored; only public tool binaries were handled, no secret material. ✅ As accepted.

## Commits

- `8681e85` feat(06): bootstrap scaffold Go module and cobra CLI skeleton
- `d68c27d` chore(06): gitignore stray scaffold build artifact

## Self-Check: PASSED

- scaffold/go.mod — FOUND
- scaffold/go.sum — FOUND
- scaffold/cmd/scaffold/main.go — FOUND
- scaffold/README.md — FOUND
- scaffold/.gitignore — FOUND
- commit 8681e85 — FOUND
- commit d68c27d — FOUND
