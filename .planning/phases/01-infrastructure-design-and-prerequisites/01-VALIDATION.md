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
| INFRA-03 | Every managed guest has explicit positive CPU, memory, and disk allocations; unique IP/DNS identity; valid startup order; resolved required facts; and aggregate capacity preserving the approved reserve | schema/policy integration | `bash tests/test-inventory.sh` | Wave 0 in Plans 01-01 and 01-02; final gate in Plan 01-05 |

## Sampling Rate

- **After every task commit:** Run the task-specific command in the map below; once the validator exists, also run `scripts/validate-inventory.sh infrastructure/inventory.json` when the task modifies the inventory or validator.
- **After every plan wave:** Run `bash tests/test-inventory.sh` after Wave 2 creates the suite. In Wave 1, use the mapped `jq` checks because the suite does not yet exist.
- **Before `$gsd-verify-work`:** Run `bash tests/test-inventory.sh && scripts/validate-inventory.sh infrastructure/inventory.json`; both must be green.
- **Max feedback latency:** 10 seconds for automated checks. Plan 01-04 is the documented human-checkpoint exception and blocks until operator evidence is supplied.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | INFRA-03 | T-01-01, T-01-02 | Canonical host/network/capacity contract contains explicit reserve policy without secret values | schema | `jq -e '.schema_version and .site.proxmox and .site.network and .capacity.policy and (.capacity.policy.minimum_memory_headroom_percent.value == 20) and (.capacity.policy.minimum_storage_headroom_percent.value == 20)' infrastructure/inventory.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | INFRA-03 | T-01-03, T-01-04 | Guest allocations, ownership, dependencies, and credential descriptors are explicit | schema | `jq -e '([.guests[].id] \| sort) == (["debezium-01","k3s-01","nats-01","postgres-01","valkey-01","zitadel-existing"] \| sort) and (all(.guests[]; (.resources.vcpu.value // 1) > 0 and (.resources.memory_mib.value // 1) > 0 and (.resources.disk_gib.value // 1) > 0)) and ([.credentials[].system] \| sort) == (["cloudflare","github","ghcr","mikrotik-lan","npm","proxmox"] \| sort)' infrastructure/inventory.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 2 | INFRA-03 | T-01-05, T-01-06 | Validator rejects malformed identities, unresolved facts, and secret-shaped content | static | `bash -n scripts/validate-inventory.sh && test -x scripts/validate-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 2 | INFRA-03 | T-01-07 | Validator enforces capacity and ownership boundaries | static | `bash -n scripts/validate-inventory.sh && rg -q 'headroom|capacity' scripts/validate-inventory.sh && rg -q 'argocd|Argo' scripts/validate-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 2 | INFRA-03 | T-01-05 through T-01-09 | Fixtures prove valid acceptance and unsafe-input rejection paths | integration | `bash tests/test-inventory.sh` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 2 | INFRA-03 | T-01-08 | Prerequisite checklist covers each external system and secret-safe evidence process | content | `for term in Proxmox Mikrotik NPM Cloudflare GitHub GHCR '20%' 'inventory.json'; do rg -qi "$term" docs/prerequisites.md || exit 1; done` | ❌ W0 | ⬜ pending |
| 01-03-02 | 03 | 2 | INFRA-03 | T-01-09 | Architecture document preserves approved ownership and lifecycle boundaries | content | `for term in 'single-node' 'native-service' Zitadel 'Argo CD' OpenTofu 'configuration automation' 'local-first'; do rg -qi "$term" docs/architecture-boundaries.md || exit 1; done` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 3 | INFRA-03 | T-01-10, T-01-11 | Operator supplies source-dated non-secret facts and access outcomes | human checkpoint | `MISSING — explicit human-checkpoint exception: target-system facts cannot be independently observed by repository automation; Plan 01-04 blocks and Plan 01-05 validates the transferred evidence` | N/A | ⬜ pending |
| 01-05-01 | 05 | 4 | INFRA-03 | T-01-12 | Only evidenced facts receive verified status | policy | `jq -e 'all(.. \| objects \| select(has("status") and has("validation")); .status == "verified")' infrastructure/inventory.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-05-02 | 05 | 4 | INFRA-03 | T-01-13, T-01-14 | Complete contract passes capacity, identity, ownership, and secret-material gates | integration | `bash tests/test-inventory.sh && scripts/validate-inventory.sh infrastructure/inventory.json && ! rg -n 'BEGIN (RSA \|EC \|OPENSSH )?PRIVATE KEY\|Authorization:[[:space:]]*(Bearer\|Basic)' infrastructure docs` | ❌ W0 | ⬜ pending |

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
| Verify measured Proxmox/site facts, reserved platform identities, budget acceptance, and credential storage descriptor/access outcomes | INFRA-03 | These facts reside in operator-controlled Proxmox, Mikrotik, NPM, Zitadel, Cloudflare, and GitHub environments that repository automation cannot independently observe in Phase 1 | Execute the read-only checklist in `docs/prerequisites.md`; provide sources and timestamps but no credential values. Plan 01-04 records the evidence. Plan 01-05 transfers it, refuses unresolved fields, and runs the complete automated gate. |

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
