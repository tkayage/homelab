---
phase: 01
slug: infrastructure-design-and-prerequisites
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-07
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash + `jq` 1.7 |
| **Config file** | none — Wave 0 creates the test harness |
| **Quick run command** | `scripts/validate-inventory.sh infrastructure/inventory.json` |
| **Full suite command** | `bash tests/test-inventory.sh` |
| **Estimated runtime** | < 10 seconds |

---

## Requirement Test Map

| Req ID | Behavior | Test Type | Automated Command | Coverage |
|--------|----------|-----------|-------------------|----------|
| INFRA-03 | Every managed guest has explicit positive CPU, memory, and disk allocations; existing Zitadel has complete observed identity/capacity/startup evidence; identities and startup order are valid; required facts are resolved; and aggregate capacity preserves approved CPU, RAM, and storage policy thresholds | schema/policy integration | `bash tests/test-inventory.sh` | Wave 0 in Plans 01-01 and 01-02; structured prerequisite checks in Plan 01-03; final gate in Plan 01-05 |

## Sampling Rate

- **After every task commit:** Run the task-specific command in the map below; once the validator exists, also run `scripts/validate-inventory.sh infrastructure/inventory.json` when the task modifies the inventory or validator.
- **After every plan wave:** Run `bash tests/test-inventory.sh` after Wave 2 creates the suite. In Wave 1, use the mapped `jq` checks because the suite does not yet exist.
- **Before `$gsd-verify-work`:** Run `bash tests/test-inventory.sh && scripts/validate-inventory.sh infrastructure/inventory.json`; both must be green.
- **Max feedback latency:** 10 seconds for automated checks. Plan 01-04 is the documented human-checkpoint exception and blocks until operator evidence is supplied.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | INFRA-03 | T-01-01, T-01-02 | Canonical host/network/capacity contract contains a measurable CPU mode/threshold and explicit RAM/storage reserves without secret values | schema | `jq -e '.schema_version and .site.proxmox and .site.network and .capacity.policy and (.capacity.policy.cpu.mode.value \| IN("minimum_uncommitted_thread_percent","maximum_vcpu_overcommit_ratio")) and (.capacity.policy.cpu.threshold.value \| numbers) and (.capacity.policy.minimum_memory_headroom_percent.value == 20) and (.capacity.policy.minimum_storage_headroom_percent.value == 20)' infrastructure/inventory.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | INFRA-03 | T-01-03, T-01-04 | Guest allocations, ownership, dependencies, credential descriptors, and all blocked Zitadel observation fields are explicit | schema | Plan 01-01 Task 2 exact `jq` structural command | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 2 | INFRA-03 | T-01-05, T-01-06 | Validator rejects malformed identities, unresolved facts, and secret-shaped content | static | `bash -n scripts/validate-inventory.sh && test -x scripts/validate-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 2 | INFRA-03 | T-01-07 | Validator enforces selected CPU arithmetic, RAM/storage headroom, Zitadel completeness, and ownership boundaries | static | `bash -n scripts/validate-inventory.sh && rg -q 'minimum_uncommitted_thread_percent\|maximum_vcpu_overcommit_ratio' scripts/validate-inventory.sh && rg -q 'zitadel-existing' scripts/validate-inventory.sh && rg -q 'argocd\|Argo' scripts/validate-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 2 | INFRA-03 | T-01-05 through T-01-09 | Fixtures prove valid acceptance and reject CPU-policy breaches plus unresolved Zitadel evidence | integration | `bash tests/test-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 2 | INFRA-03 | T-01-08 | Prerequisite tables contain exact inventory paths, all external-system access-control fields, CPU approval fields, and every Zitadel observed field | structured content | `bash -c 'set -e; f=docs/prerequisites.md; for path in site.proxmox site.network capacity.host.physical_threads capacity.commitments.existing_vcpu capacity.policy.cpu guests.zitadel-existing.resources.vcpu guests.zitadel-existing.resources.memory_mib guests.zitadel-existing.resources.disk_gib guests.zitadel-existing.network.ipv4 guests.zitadel-existing.network.dns guests.zitadel-existing.startup.order guests.zitadel-existing.startup.delay_seconds; do rg -q "^[|][[:space:]]*${path//./\\.}[[:space:]]*[|]" "$f"; done; for system in proxmox mikrotik-lan npm cloudflare github ghcr; do rg -q "^[|][[:space:]]*$system[[:space:]]*[|]" "$f"; done; rg -q "minimum scope.*secret-store.*consumers.*rotation.*revocation.*verification.*outcome.*source.*timestamp" "$f"'` | ❌ W0 | ⬜ pending |
| 01-03-02 | 03 | 2 | INFRA-03 | T-01-09 | Responsibility table has every required capability, canonical ownership columns, and no duplicated mutable addresses or resource sizes | structured content | `bash -c 'set -e; f=docs/architecture-boundaries.md; for id in k3s-01 postgres-01 valkey-01 nats-01 debezium-01 zitadel-existing kubernetes-desired-state vm-lxc-lifecycle native-service-configuration local-exposure public-opt-in; do rg -q "^[|][[:space:]]*$id[[:space:]]*[|]" "$f"; done; rg -q "canonical inventory.*lifecycle owner.*configuration owner.*state class.*trust boundary" "$f"; ! rg -n "^[|].*([0-9]{1,3}\\.){3}[0-9]{1,3}.*[|]$\|^[|].*[0-9]+[[:space:]]*(MiB\|GiB\|vCPU).*[|]$" "$f"'` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 3 | INFRA-03 | T-01-10, T-01-11 | Operator supplies source-dated non-secret facts, selected measurable CPU policy and approval, complete Zitadel observations, and access outcomes | human checkpoint | `MISSING — explicit human-checkpoint exception: target-system facts cannot be independently observed by repository automation; Plan 01-04 blocks and Plan 01-05 validates the transferred evidence` | N/A | ⬜ pending |
| 01-05-01 | 05 | 4 | INFRA-03 | T-01-12 | Only evidenced facts receive verified status | policy | `jq -e 'all(.. \| objects \| select(has("status") and has("validation")); .status == "verified")' infrastructure/inventory.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-05-02 | 05 | 4 | INFRA-03 | T-01-13, T-01-14 | Complete contract passes CPU/RAM/storage capacity, Zitadel evidence, identity, ownership, and secret-material gates | integration | `bash tests/test-inventory.sh && scripts/validate-inventory.sh infrastructure/inventory.json && ! rg -n 'BEGIN (RSA \|EC \|OPENSSH )?PRIVATE KEY\|Authorization:[[:space:]]*(Bearer\|Basic)' infrastructure docs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `infrastructure/inventory.json` — canonical contract created by Plan 01-01 for INFRA-03.
- [ ] `scripts/validate-inventory.sh` — structural, identity, secret-safety, capacity, and ownership policy gate created by Plan 01-02.
- [ ] `tests/test-inventory.sh` — full acceptance/rejection suite created by Plan 01-02.
- [ ] `tests/fixtures/invalid-inventory.json` — baseline rejection fixture or mutation source created by Plan 01-02.
- [ ] `docs/prerequisites.md` and `docs/architecture-boundaries.md` — machine-checkable operator and ownership contracts created by Plan 01-03.

Wave 0 is fully assigned to Plans 01-01 through 01-03. `wave_0_complete` remains false until execution creates these files and their mapped commands pass.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Verify measured Proxmox/site facts, reserved platform identities, measurable CPU policy approval, RAM/storage budget acceptance, complete observed Zitadel capacity/identity/startup facts, and credential storage descriptor/access outcomes | INFRA-03 | These facts reside in operator-controlled Proxmox, Mikrotik, NPM, Zitadel, Cloudflare, and GitHub environments that repository automation cannot independently observe in Phase 1 | Execute the read-only checklist in `docs/prerequisites.md`; provide sources and timestamps but no credential values. Plan 01-04 records the evidence. Plan 01-05 transfers it, refuses unresolved fields or threshold breaches, and runs the complete automated gate. |

This is the only human-checkpoint exception. It does not waive automated validation: Phase 1 remains incomplete until Plan 01-05's full suite and validator pass.

---

## Validation Sign-Off

- [x] All tasks have an automated verification command, a Wave 0 dependency, or the explicit Plan 01-04 human-checkpoint exception.
- [x] Sampling continuity: no three consecutive tasks lack automated verification.
- [x] Wave 0 covers all currently missing test and contract files.
- [x] No watch-mode flags are used.
- [x] Expected automated feedback latency is under 10 seconds.
- [x] `nyquist_compliant: true` is set in frontmatter.

**Approval:** strategy approved 2026-07-07; execution pending
