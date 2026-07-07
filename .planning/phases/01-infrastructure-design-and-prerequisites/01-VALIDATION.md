---
phase: 01
slug: infrastructure-design-and-prerequisites
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-07-07
revised: 2026-07-07
---

# Phase 01 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | Bash + `jq` 1.7 |
| Quick run | `scripts/validate-inventory.sh infrastructure/inventory.json` |
| Full suite | `bash tests/test-inventory.sh` |
| Expected runtime | under 10 seconds |

## Requirement Test Map

| Req ID | Behavior | Test Type | Automated Command | Coverage |
|--------|----------|-----------|-------------------|----------|
| INFRA-03 | Exactly three new guests have fixed allocations and identities: native PostgreSQL LXC, supporting-services Compose VM, and disposable k3s VM; Valkey, NATS/JetStream, and Debezium are internal services; Docker-in-LXC is prohibited; existing Zitadel evidence and approved capacity thresholds are complete | schema/policy integration | `bash tests/test-inventory.sh` | Historical framework in Plans 01-01 through 01-03; contract migration in Plan 01-05; validator remediation in Plan 01-06; final gate in Plan 01-07 |

## Sampling Rate

- After an inventory, validator, test, or fixture task: run `bash tests/test-inventory.sh` and `scripts/validate-inventory.sh infrastructure/inventory.json` when the canonical inventory is expected to be resolved.
- After documentation changes: run the task's exact `rg`/`jq` structural command.
- Before verification: run the complete Plan 01-07 Task 1 command.
- Plan 01-04 is the sole human-checkpoint exception because it records operator-controlled system evidence and approvals.

## Per-Task Verification Map

| Task ID | Plan | Wave | Behavior | Automated Command | Status |
|---------|------|------|----------|-------------------|--------|
| 01-01-01 | 01 | 1 | Historical site/capacity schema established | Plan 01-01 summary self-check | ✅ green |
| 01-01-02 | 01 | 1 | Historical guest, ownership, credential, and Zitadel schema established | Plan 01-01 summary self-check | ✅ green |
| 01-02-01 | 02 | 2 | Structural, identity, evidence, and secret-safety validator established | `bash -n scripts/validate-inventory.sh && test -x scripts/validate-inventory.sh` | ✅ green |
| 01-02-02 | 02 | 2 | Capacity, Zitadel, and ownership policy enforcement established | Plan 01-02 summary self-check | ✅ green |
| 01-02-03 | 02 | 2 | Acceptance/rejection fixture framework established | Plan 01-02 summary self-check | ✅ green |
| 01-03-01 | 03 | 2 | Prerequisite and evidence checklist established | Plan 01-03 summary self-check | ✅ green |
| 01-03-02 | 03 | 2 | Ownership and trust-boundary contract established | Plan 01-03 summary self-check | ✅ green |
| 01-04-01 | 04 | 3 | Operator records source-dated facts, exact three-guest approval, capacity policies, Zitadel observations, and access outcomes | Human-checkpoint exception; Plan 01-05 validates transferred evidence | ⬜ pending |
| 01-05-01 | 05 | 4 | Inventory/docs contain only postgres-01, services-01, and k3s-01 as new guests and model embedded Compose services | Plan 01-05 Task 1 exact `jq` and `rg` command | ⬜ pending |
| 01-06-01 | 06 | 5 | Validator/tests accept consolidated topology and reject legacy guests, missing services, Docker-in-LXC, and policy violations | `bash -n scripts/validate-inventory.sh && bash tests/test-inventory.sh` | ⬜ pending |
| 01-07-01 | 07 | 6 | Resolved contract passes topology, capacity, evidence, ownership, and value-suppressing secret-material gates including the checkpoint summary | Plan 01-07 Task 1 exact command | ⬜ pending |

## Existing Test Assets and Remediation

- [x] `infrastructure/inventory.json` exists; Plan 01-05 migrates its obsolete per-service guests.
- [x] `scripts/validate-inventory.sh` exists; Plan 01-06 replaces fixed legacy topology assertions.
- [x] `tests/test-inventory.sh` and focused fixtures exist; Plan 01-06 updates their accepted/rejected topology.
- [x] `docs/prerequisites.md` and `docs/architecture-boundaries.md` exist; Plan 01-05 updates guest and service rows.

## Manual-Only Verification

| Behavior | Why Manual | Follow-through |
|----------|------------|----------------|
| Verify Proxmox/site measurements, identity reservations, 2.5 maximum vCPU/thread approval, 20% RAM/storage reserves, existing Zitadel observations, and credential access/storage descriptors | These facts live in operator-controlled systems | Plan 01-04 records non-secret evidence; Plan 01-05 refuses unresolved fields or threshold breaches and runs the automated gate |

## Source Coverage Audit

| Source | ID | Item | Plan | Status |
|--------|----|------|------|--------|
| GOAL | — | Executable resource, network, identity, and bootstrap prerequisite contract | 01-01 through 01-07 | COVERED |
| REQ | INFRA-03 | Explicit network, CPU, memory, and storage allocations | 01-05 through 01-07 | COVERED |
| RESEARCH | — | Capacity reserves, evidence gating, ownership, startup/readiness, and secret safety | 01-02 through 01-07 | COVERED |
| CONTEXT | — | Machine-readable inventory, secret-free evidence, no provisioning in Phase 1 | 01-01 through 01-07 | COVERED |
| USER | — | PostgreSQL LXC; shared Compose VM; separate k3s VM; no Docker-in-LXC; no other new LXCs | 01-04 through 01-07 | COVERED |

## Sign-Off

- [x] Every task has an automated command or the explicit Plan 01-04 checkpoint exception.
- [x] Executed plan history remains represented as completed.
- [x] Plans 01-05, 01-06, and 01-07 separately own contract/docs migration, validator/fixture remediation, and the final gate.
- [x] No watch-mode command is used.
- [x] Expected automated feedback latency is under 10 seconds.
