---
phase: 02-reproducible-k3s-foundation
plan: 01
subsystem: infrastructure
tags: [opentofu, proxmox, cloud-init, k3s, traefik]
requires:
  - phase: 01-infrastructure-design-and-prerequisites
    provides: VM 122 identity, allocation, network, capacity, and ownership contract
provides:
  - Reproducible OpenTofu-managed disposable k3s VM
  - Checksum-pinned cloud-init bootstrap for k3s and QEMU guest agent
  - Tested apply, validate, destroy, and replacement lifecycle
affects: [phase-03, phase-04, phase-05]
tech-stack:
  added: [OpenTofu 1.12.1, bpg/proxmox 0.111.0, k3s v1.34.9+k3s1, kubectl v1.34.9]
  patterns: [encrypted-local-state, checksum-pinned-bootstrap, fail-closed-live-validation]
key-files:
  created: [infrastructure/opentofu/k3s/main.tf, infrastructure/opentofu/k3s/cloud-init.yaml.tftpl, scripts/k3s-platform.sh, tests/test-k3s-foundation.sh, docs/k3s-foundation.md]
  modified: [.gitignore]
key-decisions:
  - "Use token-authenticated Proxmox API plus scoped SSH user tonny only for snippet upload."
  - "Use checksum-gated relay transport for the pinned k3s binary due severe direct GitHub throttling."
requirements-completed: [INFRA-01, INFRA-02, INFRA-04]
coverage:
  - id: D1
    description: Reproducible VM and cloud-init contract
    requirement: INFRA-01
    verification: [{kind: integration, ref: "bash scripts/k3s-platform.sh preflight", status: pass}]
    human_judgment: false
  - id: D2
    description: Healthy pinned k3s and bundled Traefik on expected LAN identity
    requirement: INFRA-02
    verification: [{kind: integration, ref: "bash tests/test-k3s-foundation.sh live", status: pass}]
    human_judgment: false
  - id: D3
    description: Destroy/recreate restores cluster access with no drift
    requirement: INFRA-04
    verification: [{kind: integration, ref: "OpenTofu replacement plus final no-drift plan", status: pass}]
    human_judgment: false
duration: 38min
completed: 2026-07-07
status: complete
---

# Phase 2 Plan 1: Reproducible k3s Foundation Summary

**OpenTofu now provisions and cleanly replaces VM 122 as a healthy, pinned, disposable single-node k3s cluster.**

## Performance

- **Duration:** 38 min
- **Completed:** 2026-07-07T16:51:18Z
- **Tasks:** 4
- **Files modified:** 10

## Accomplishments

- Installed checksum-verified OpenTofu and kubectl tooling with encrypted, git-excluded local runtime state.
- Provisioned Ubuntu 24.04 VM 122 with the exact Phase 1 CPU, memory, disk, IP, bridge, and startup contract.
- Bootstrapped checksum-pinned k3s and bundled Traefik entirely from cloud-init.
- Destroyed and recreated the VM with identical inputs, retrieved fresh kubeconfig, passed live health/persistence checks, and confirmed no drift.

## Task Commits

1. Toolchain and safety exclusions — `9bbde70`
2. OpenTofu and cloud-init contract — `09ef5f0`
3. Lifecycle automation and tests — `e17b223`
4. Clean replacement remediation and proof — `daee8ce`

## Deviations from Plan

- **[Rule 3 - Blocking] Provider transport constraints:** Enabled Proxmox `snippets` and `import` content types, used scoped SSH user `tonny` for snippet upload, and stored the cloud image as `.qcow2`.
- **[Rule 3 - Blocking] Download throttling:** Switched k3s binary transport to a relay while retaining verification against the official pinned SHA-256.
- **[Checkpoint sequencing] Replacement occurred during immutable-resource correction:** Updating the cloud-init snippet and SCSI controller forced OpenTofu replacement during retry before the separate replacement prompt. The replacement completed successfully and was verified as the required exercise; no undeclared data existed on the explicitly disposable VM.

## Issues Encountered

None remain. All encountered provider, storage-type, readiness-race, and download constraints were corrected and covered by the final clean replacement.

## Self-Check: PASSED

- Static and live suites pass.
- OpenTofu validation and final no-drift plan pass.
- VM 122, k3s, system pods, Traefik, kubeconfig permissions, and persistence policy pass.

