---
phase: 07-opt-in-public-exposure
plan: 01
subsystem: public-edge
tags: [cloudflare, public-edge, default-deny, scaffold, ingress, security]
status: complete
dependency_graph:
  requires:
    - "Phase 4 LAN edge wildcard NPM -> Traefik path"
    - "Phase 6 scaffolder GitOps manifest generation"
  provides:
    - "Default-deny generated app manifests"
    - "Explicit --public/public metadata opt-in path"
    - "Public edge contract and non-mutating verification commands"
    - "Admin surface denylist scan"
  affects:
    - "Phase 8 validation app can opt into public exposure and prove full external lifecycle"
tech_stack:
  added: []
  patterns:
    - "Public exposure is represented in GitOps manifests, not implicit hostname conventions"
    - "Public DNS is per-host only; wildcard public record remains forbidden"
    - "Scripts follow existing edge conventions: Bash, jq, curl, external env credentials, no secrets in git"
key_files:
  created:
    - "infrastructure/edge/public-edge.json"
    - "scripts/public-edge.sh"
    - "tests/test-public-edge.sh"
  modified:
    - "scaffold/cmd/scaffold/main.go"
    - "scaffold/internal/scaffolder/scaffolder.go"
    - "scaffold/internal/manifests/manifests.go"
    - "scaffold/internal/manifests/manifests_test.go"
    - "scaffold/internal/manifests/testdata/apps-slug.golden.txt"
    - "scaffold/internal/templates/files/gitops/ingress.yaml.tmpl"
decisions:
  - "Default-deny remains the normal generated app behavior; `--public` is an explicit operator opt-in."
  - "Public records are per-host CNAME records to `public-edge.kayage.co`; no public wildcard is allowed."
  - "Full create/reach/disable live proof is deferred to the Phase 8 validation app to avoid exposing a throwaway service."
metrics:
  completed: 2026-07-09
  tasks_completed: 3
  files_created: 5
  files_modified: 8
  commits: 2
requirements: [PUBLIC-01, PUBLIC-02, PUBLIC-03, PUBLIC-04]
coverage:
  - id: PUBLIC-01
    description: "Applications remain LAN-only unless explicitly marked public."
    verification:
      - kind: test
        ref: "go test -C scaffold ./..."
        status: pass
      - kind: live-readonly
        ref: "bash scripts/public-edge.sh assert-default-deny edge-smoke"
        status: pass
  - id: PUBLIC-02
    description: "Public opt-in creates the required per-host Cloudflare record metadata."
    verification:
      - kind: test
        ref: "TestIngressPublicOptIn and tests/test-public-edge.sh static"
        status: pass
  - id: PUBLIC-03
    description: "Public traffic traverses the AWS Mikrotik path to NPM and Traefik."
    verification:
      - kind: contract
        ref: "infrastructure/edge/public-edge.json and scripts/public-edge.sh preflight"
        status: pass
  - id: PUBLIC-04
    description: "Public exposure defaults to deny and does not expose administrative interfaces."
    verification:
      - kind: live-readonly
        ref: "bash scripts/public-edge.sh scan-admin"
        status: pass
---

# Phase 07 Plan 01: Opt-in Public Exposure Summary

Implemented the default-deny public exposure contract and verification harness.

## Accomplishments

- Added `--public` to the scaffolder. Default remains LAN-only.
- Added `Public` through the manifest rendering path.
- Updated generated Ingress manifests to carry a review-visible public marker and only emit public external-dns annotations when explicitly opted in.
- Added `infrastructure/edge/public-edge.json` with public routing contract and management-surface denylist.
- Added `scripts/public-edge.sh` with preflight, default-deny, status, enable, disable, reachability, and admin scan commands.
- Added `tests/test-public-edge.sh static` for default-deny, per-host-only, denylist, and credential hygiene checks.

## Task Commits

1. **Task 1: Add default-deny public flag to generated GitOps manifests** — `6430256`
2. **Task 2: Add public edge contract, operator script, and static verification** — `83be89c`

## Verification Results

- `go test -C scaffold ./...` — PASS
- `bash scripts/scaffold-verify.sh all` — PASS
- `bash tests/test-public-edge.sh static` — PASS
- `bash scripts/public-edge.sh preflight` — PASS
- `bash scripts/public-edge.sh assert-default-deny edge-smoke` — PASS
- `bash scripts/public-edge.sh scan-admin` — PASS

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact:** none.

## Issues Encountered

- Full public enable/reachability/disable was not run in Phase 7 because it would intentionally create public DNS for a real app. The command path exists (`prove-enable`, `prove-reachability`, `prove-disable`) and is deferred to Phase 8's validation app.

## Self-Check: PASSED
