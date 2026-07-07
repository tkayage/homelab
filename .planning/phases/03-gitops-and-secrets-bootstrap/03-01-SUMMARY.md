---
phase: 03-gitops-and-secrets-bootstrap
plan: 01
subsystem: platform
tags: [argocd, applicationset, sops, age, gitops]
requires:
  - phase: 02-reproducible-k3s-foundation
    provides: Healthy disposable k3s cluster, kubeconfig, and SSH recovery path
provides:
  - Argo CD v3.4.2 reconciliation from the private GitOps repository
  - Automatic apps/* discovery with guarded pruning and deletion semantics
  - SOPS/age decryption through an ephemeral Config Management Plugin
  - Tested bootstrap, status, rollback, and recovery workflow
affects: [phase-04, phase-06, phase-07, phase-08]
tech-stack:
  added: [Argo CD v3.4.2, SOPS v3.13.2, age v1.3.1]
  patterns: [app-of-applications, git-directory-generator, encrypted-secrets, git-revert-rollback]
key-files:
  created: [gitops/platform/applicationset.yaml, infrastructure/kubernetes/argocd/cmp-plugin.yaml, scripts/gitops-platform.sh, tests/test-gitops-bootstrap.sh, docs/gitops-bootstrap.md]
  modified: [.gitignore]
key-decisions:
  - "Disable pruning on the platform root; generated apps prune/self-heal while preserving resources on Application deletion."
  - "Build a checksum-verified local Argo/SOPS CMP image and import it over SSH to avoid unreliable guest downloads."
  - "Keep GitHub and age private credentials outside git and restore them before the root Application."
requirements-completed: [GITOPS-01, GITOPS-02, GITOPS-05, GITOPS-06]
coverage:
  - id: D1
    description: Argo CD reconciles authoritative platform state
    requirement: GITOPS-01
    verification: [{kind: integration, ref: "platform-root Synced/Healthy", status: pass}]
    human_judgment: false
  - id: D2
    description: apps/* discovery deploys a healthy workload
    requirement: GITOPS-02
    verification: [{kind: integration, ref: "gitops-smoke Synced/Healthy", status: pass}]
    human_judgment: false
  - id: D3
    description: SOPS ciphertext decrypts using external recovery key
    requirement: GITOPS-05
    verification: [{kind: integration, ref: "decrypted cluster Secret plus ciphertext scan", status: pass}]
    human_judgment: false
  - id: D4
    description: Operator health and git revert rollback
    requirement: GITOPS-06
    verification: [{kind: integration, ref: "controlled bad commit 65a22cb reverted by 61a2c2f", status: pass}]
    human_judgment: false
duration: 34min
completed: 2026-07-07
status: complete
---

# Phase 3 Plan 1: GitOps and Secrets Bootstrap Summary

**Argo CD now reconciles the private GitOps repository, discovers applications, decrypts SOPS secrets, and recovers through Git revert.**

## Accomplishments

- Installed pinned Argo CD with a checksum-verified SOPS CMP image and external age key.
- Published the private `tkayage/gitops-homelab` repository and reconciled platform/application state.
- Proved encrypted-secret delivery without committing plaintext or recovery credentials.
- Pushed a controlled broken image, observed reconciliation, reverted commit `65a22cb`, and restored health with `61a2c2f`.
- Re-ran the documented bootstrap entry point and passed all 18 live/static checks.

## Task Commits

1. GitOps manifests, automation, tests, and documentation — `71dbbc5`
2. Deterministic recovery and ApplicationSet safety correction — `1316a23`

## Deviations from Plan

- **[Rule 3 - Blocking] Guest registry/download throughput:** Replaced pod-time SOPS downloading with a checksum-verified operator-built image imported over the existing SSH recovery path.
- **[Rule 1 - Bug] ApplicationSet field placement:** Moved `preserveResourcesOnDeletion` under `spec.syncPolicy`, where the v3.4 CRD retains and enforces it.

## Self-Check: PASSED

- Root and discovered application are Synced/Healthy.
- Encrypted Secret is materialized and consumed by the ready workload.
- Rollback proof and repeat bootstrap pass.
