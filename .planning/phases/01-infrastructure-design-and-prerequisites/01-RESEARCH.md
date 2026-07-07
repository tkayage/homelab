# Phase 1: Infrastructure Design and Prerequisites - Research

**Researched:** 2026-07-07
**Domain:** Homelab infrastructure contract, capacity planning, network identity, and credential boundaries
**Confidence:** MEDIUM

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Preserve the approved architecture: disposable single-node k3s VM, one native-service LXC per durable service, existing Zitadel retained, GitOps ownership limited to Kubernetes resources, and local-first exposure.
- Never commit credentials or secret values; document names, scopes, storage locations, and acquisition checks only.

### the agent's Discretion
- All implementation choices are at Codex's discretion for this pure infrastructure phase.
- Prefer machine-readable inventories with documented placeholder values where environment-specific facts are unavailable.

### Deferred Ideas (OUT OF SCOPE)
Actual provisioning, credential creation, router changes, and external-service mutations belong to their respective later phases.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-03 | Infrastructure configuration defines explicit network, CPU, memory, and storage allocations. | Define a schema-validated JSON inventory containing every VM/LXC allocation, identity, dependency, startup order, assumption, and validation state; derive aggregate capacity and headroom from it. |
</phase_requirements>

## Summary

Phase 1 should produce an executable contract, not provision infrastructure. The repository currently contains planning documents only, while `jq` is available and OpenTofu, Terraform, Ansible, `yq`, and `kubectl` are not installed. [VERIFIED: repository scan and local CLI probes] The most reliable Wave 0 is therefore a dependency-free JSON inventory plus shell/`jq` validation and operator-facing Markdown generated or checked from that canonical data.

The contract must separate known facts from proposed defaults and unresolved site facts. Exact MS-01 capacity, Proxmox version/node/bridge/storage names, subnet/VLAN, DNS zone, reserved addresses, and existing NPM/Zitadel identities are not present in the repository. [VERIFIED: `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/research/`, and `01-CONTEXT.md`] Planning must not silently convert those unknowns into facts. Proposed guest sizes are starting budgets, tagged `[ASSUMED]`, and must be accepted only after capacity and workload checks.

**Primary recommendation:** Create one canonical `infrastructure/inventory.json`, validate it with `scripts/validate-inventory.sh`, and generate/check `docs/prerequisites.md` without ever placing secret values in repository files.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Guest sizing and identity | OpenTofu/external infrastructure | Proxmox | OpenTofu will consume the contract; Proxmox is the execution target. [VERIFIED: project architecture] |
| Kubernetes desired state | Argo CD | k3s | Argo CD owns resources inside the cluster only. [VERIFIED: `01-CONTEXT.md`] |
| Native service configuration | Configuration automation | Proxmox LXCs | OpenTofu creates containers; later configuration automation installs native services. [VERIFIED: `.planning/research/STACK.md`] |
| LAN/public edge | OpenTofu/configuration automation | Mikrotik, NPM, Cloudflare | These resources exist outside Kubernetes and must not be owned by Argo CD. [VERIFIED: project architecture] |
| Credential material | Operator secret stores / platform secret bootstrap | GitHub and cluster consumers | Git stores names and scopes, never plaintext values. [VERIFIED: `01-CONTEXT.md`] |
| Capacity gate | Inventory validator | Operator | Aggregate allocations and reserved headroom must be checked before provisioning. [ASSUMED] |

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| JSON | RFC 8259 | Canonical machine-readable inventory | Native to tooling and validates with installed `jq`; avoids adding a parser dependency. [VERIFIED: local CLI probe] |
| `jq` | 1.7 | Structural, uniqueness, arithmetic, and policy checks | Already available on the control machine. [VERIFIED: `jq --version`] |
| POSIX/Bash shell | system-provided | Reproducible validation entry point | No package install is required for Phase 1. [VERIFIED: local environment] |
| OpenTofu | not installed; pin in Phase 2 | Future consumer of the contract | Approved external-infrastructure ownership tool. [VERIFIED: `.planning/research/STACK.md`] |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Markdown | repository format | Human prerequisite and credential checklist | Record acquisition tests, ownership, and operator decisions. [VERIFIED: repository convention] |
| Git | 2.43.0 | Review and audit contract changes | Commit inventory and validation changes atomically. [VERIFIED: `git --version`] |

No external package is installed in this phase, so package-legitimacy auditing is not applicable.

## Architecture Patterns

### System Architecture Diagram

```text
operator-supplied site facts
          |
          v
infrastructure/inventory.json -----> scripts/validate-inventory.sh
          |                                      |
          | valid                                | invalid
          v                                      v
docs/prerequisites.md                    actionable errors / stop
          |
          +------ Phase 2: OpenTofu VM contract
          +------ Phase 3: bootstrap credential names/scopes
          +------ Phase 4: DNS/NPM/Cloudflare identities
          +------ Phase 5: LXC sizes, names, addresses, ordering
```

### Recommended Project Structure

```text
infrastructure/
└── inventory.json             # canonical secret-free contract
docs/
└── prerequisites.md           # access checks and human-readable decisions
scripts/
└── validate-inventory.sh      # fast policy/schema checks using jq
tests/
└── fixtures/
    └── invalid-inventory.json # proves rejection paths
```

### Pattern 1: Canonical inventory with explicit evidence state

Every environment-specific field should be an object containing `value`, `status` (`proposed`, `verified`, or `blocked`), and `validation` text. [ASSUMED] This prevents placeholders such as `192.168.1.20` from looking production-ready.

```json
{
  "network": {
    "bridge": {"value": "REPLACE_ME", "status": "blocked", "validation": "Confirm with Proxmox network configuration"}
  },
  "guests": [{
    "id": "k3s-01",
    "kind": "vm",
    "resources": {"vcpu": 4, "memory_mib": 8192, "disk_gib": 64},
    "network": {"ipv4": "REPLACE_ME", "dns_name": "k3s-01.REPLACE_ME"},
    "startup": {"order": 40, "up_delay_seconds": 30},
    "status": "proposed"
  }]
}
```

### Pattern 2: Budget from measured host capacity

Record physical cores/threads, usable memory, usable datastore space, existing committed allocations, proposed new allocations, and minimum reserve. Compute the gate rather than writing “enough headroom.” [ASSUMED] A conservative initial policy is at least 20% usable RAM and datastore capacity unallocated after all existing and proposed guests, but the operator must confirm this threshold. [ASSUMED]

Initial proposed allocations for planning are: k3s VM 4 vCPU/8 GiB/64 GiB; Postgres 2 vCPU/4 GiB/64 GiB; Valkey 1 vCPU/2 GiB/16 GiB; NATS 1 vCPU/2 GiB/32 GiB; Debezium 2 vCPU/4 GiB/16 GiB. [ASSUMED] Existing Zitadel must be inventoried with observed allocations rather than resized in this phase. [VERIFIED: phase boundary]

### Pattern 3: Credential descriptors, never credential values

Each prerequisite entry should include system, logical name, owner, minimum scope, storage location, consumers, rotation/revocation procedure, and a non-secret verification command. [ASSUMED] Cloudflare tokens should be zone-scoped rather than global API keys. [CITED: https://developers.cloudflare.com/fundamentals/api/get-started/create-token/]

### Pattern 4: Explicit ownership and dependency ordering

The inventory should assign `owner` (`opentofu`, `config-automation`, `argocd`, or `manual-existing`) and `depends_on` to every managed object. [ASSUMED] Use Proxmox startup order only for host restart sequencing; keep application/service readiness checks in later configuration and verification phases. Proxmox supports startup/shutdown ordering and startup delays for guests. [CITED: https://pve.proxmox.com/pve-docs/pve-admin-guide.html#qm_startup_and_shutdown]

Recommended proposed startup groups: Postgres order 10; Valkey and NATS order 20; existing Zitadel recorded at its observed order; Debezium order 30 after Postgres/NATS; k3s order 40. [ASSUMED]

### Anti-Patterns to Avoid

- **Parallel inventories:** Do not independently maintain the same IPs and sizes in Markdown and HCL; one must be generated or checked from the canonical JSON. [ASSUMED]
- **Plausible placeholders:** Reject `REPLACE_ME`, example domains, duplicate IPs, duplicate guest IDs, and any `blocked` required field at the phase gate. [ASSUMED]
- **Secrets-shaped fields:** Reject keys such as `password`, `token`, `private_key`, `client_secret`, and `api_key` anywhere in the inventory. Store only descriptor names and scopes. [ASSUMED]
- **CPU-only headroom:** RAM and datastore exhaustion are credible limits on this topology, so the capacity gate must cover all three resource dimensions. [ASSUMED]
- **Argo CD owning external resources:** This violates the approved platform boundary and creates bootstrap/deletion coupling. [VERIFIED: `01-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing and arithmetic | Ad-hoc grep/sed parser | `jq` | Correct structural parsing is already available. [VERIFIED: local CLI probe] |
| Infrastructure lifecycle | Custom Proxmox API scripts | OpenTofu plus the approved Proxmox provider in Phase 2 | Plan/diff/state semantics are required later. [VERIFIED: `.planning/research/STACK.md`] |
| Secret storage | Encryption format or plaintext `.env` convention | SOPS+age/bootstrap strategy in Phase 3 and operator password manager/offline backup | Cryptographic and recovery concerns are outside this phase. [VERIFIED: approved architecture] |
| Capacity facts | Guessed MS-01 specifications | Proxmox/host measurements copied into verified inventory fields | Installed RAM and datastore capacity vary by deployment. [ASSUMED] |

**Key insight:** Phase 1's value is a hard input gate for later automation; it should make unknown facts and unsafe secret handling fail visibly.

## Common Pitfalls

### Pitfall 1: Proposed values become accidental production facts
**What goes wrong:** Example subnets, bridges, storage pools, or domain names reach provisioning.
**Why it happens:** Scalar values carry no evidence state.
**How to avoid:** Require status and validation metadata, then reject unresolved required fields.
**Warning signs:** `REPLACE_ME`, `.example`, or `proposed` remains when the phase gate runs. [ASSUMED]

### Pitfall 2: Overcommit is hidden by incomplete accounting
**What goes wrong:** New guests fit on paper but leave inadequate RAM or disk for Proxmox and existing workloads.
**Why it happens:** The budget omits existing allocations, host reserve, or storage free space.
**How to avoid:** Validate totals against measured usable capacity and a separately approved reserve.
**Warning signs:** No timestamp/source on capacity measurements or no post-allocation percentage. [ASSUMED]

### Pitfall 3: Credentials leak through “documentation”
**What goes wrong:** A real token is pasted into a checklist or sample command.
**Why it happens:** Prerequisite docs mix descriptor and value.
**How to avoid:** Use environment-variable names and redacted verification commands; add secret-key-name and entropy-pattern scans.
**Warning signs:** Long opaque strings, PEM blocks, or literal authorization headers in git. [ASSUMED]

### Pitfall 4: Duplicate or unstable identities
**What goes wrong:** Two guests claim one IP, service manifests hard-code a stale address, or DNS names differ across phases.
**Why it happens:** Identity is re-entered in multiple artifacts.
**How to avoid:** Validate unique guest IDs/IPs/DNS names and require every downstream phase to consume the inventory.
**Warning signs:** IP literals appear outside the canonical inventory. [ASSUMED]

## Code Examples

### Fast inventory policy check

```bash
#!/usr/bin/env bash
set -euo pipefail
file=${1:-infrastructure/inventory.json}
jq -e '
  (.guests | length > 0) and
  ([.guests[].id] | length == (unique | length)) and
  ([.guests[].network.ipv4] | length == (unique | length)) and
  (all(.guests[];
    .resources.vcpu > 0 and
    .resources.memory_mib > 0 and
    .resources.disk_gib > 0 and
    (.network.ipv4 | test("REPLACE_ME") | not) and
    (.network.dns_name | test("REPLACE_ME|\\.example$") | not)))
' "$file" >/dev/null
```

### Repository secret-shape guard

```bash
if jq -e '.. | objects | keys[] | select(test("^(password|token|private_key|client_secret|api_key)$"; "i"))' \
  infrastructure/inventory.json | grep -q .; then
  echo "forbidden secret-shaped key in inventory" >&2
  exit 1
fi
```

These examples are project-specific policy proposals and are therefore `[ASSUMED]`; tests must prove their intended acceptance and rejection behavior.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manually maintained host spreadsheet | Versioned machine-readable inventory with validation | Not applicable; project design choice | Later provisioning can consume reviewed inputs. [ASSUMED] |
| Terraform CLI under BUSL licensing | OpenTofu for this project | Project decision recorded 2026-07-07 | Keeps the infrastructure workflow on the approved open-source tool. [VERIFIED: `.planning/research/STACK.md`] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | JSON plus `jq` is the canonical contract/validator format. | Standard Stack | Planner may prefer YAML/HCL and need different validation tooling. |
| A2 | Maintain at least 20% usable RAM and datastore reserve. | Architecture Pattern 2 | Too low risks contention; too high may unnecessarily constrain workloads. |
| A3 | Proposed guest allocations are adequate starting points. | Architecture Pattern 2 | Under-sizing causes instability; over-sizing reduces headroom. |
| A4 | Proposed startup orders reflect service dependencies. | Architecture Pattern 4 | Restart recovery could be delayed or services could start before dependencies. |
| A5 | Status metadata and listed policy checks are sufficient phase gates. | Patterns/Pitfalls | Missing validation could allow unsafe inputs downstream. |

## Open Questions

1. **What are the measured host and Proxmox facts?**
   - What we know: The target is one MS-01 running Proxmox. [VERIFIED: project context]
   - What's unclear: PVE version, node name, cores/threads, installed/usable RAM, storage pools/free space, existing allocations, bridge, VLAN, subnet, gateway, and template IDs.
   - Recommendation: Make these blocking `verified` inventory fields before approving Phase 1.
2. **What identity range is reserved for platform guests?**
   - What we know: k3s and service LXCs need stable LAN identities. [VERIFIED: roadmap]
   - What's unclear: Exact IPs, DNS suffix, DHCP exclusion, and existing NPM/Zitadel addresses.
   - Recommendation: Reserve and collision-check a contiguous static range with the Mikrotik lease/static-DNS state.
3. **Where will each credential live?**
   - What we know: Proxmox, Mikrotik, NPM, Cloudflare, GitHub, and GHCR access is required without plaintext secrets in git. [VERIFIED: roadmap]
   - What's unclear: Password-manager/offline backup locations and exact account/repository/zone ownership.
   - Recommendation: Record descriptors and verification outcomes only; defer credential creation to its owning phase.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Bash | validator | yes | system shell | — |
| `jq` | JSON validation | yes | 1.7 | — |
| Git | audit trail | yes | 2.43.0 | — |
| SSH | read-only prerequisite probes | yes | OpenSSH client present | Document manual values if target access is unavailable |
| OpenTofu | Phase 2 consumer | no | — | Not required to complete Phase 1; installation belongs in Phase 2 Wave 0 |
| Ansible | Phase 5 consumer | no | — | Not required to complete Phase 1 |
| `kubectl` | later cluster verification | no | — | Not required before the cluster exists |

**Missing dependencies with no fallback:** None for the Phase 1 contract and validator.

**Missing dependencies with fallback:** Target-system access can be represented as `blocked` during authoring, but Phase 1 cannot pass until required site facts are verified.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash + `jq` 1.7 |
| Config file | none — see Wave 0 |
| Quick run command | `bash scripts/validate-inventory.sh` |
| Full suite command | `bash tests/test-inventory.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-03 | Every managed guest has positive CPU/memory/disk, unique IP/DNS identity, startup order, and resolved required facts; aggregate allocation preserves approved reserve | schema/policy integration | `bash tests/test-inventory.sh` | no — Wave 0 |

### Sampling Rate
- **Per task commit:** `bash scripts/validate-inventory.sh`
- **Per wave merge:** `bash tests/test-inventory.sh`
- **Phase gate:** Full suite green plus operator verification of external prerequisite checks

### Wave 0 Gaps
- [ ] `infrastructure/inventory.json` — canonical contract with proposed and blocked fields
- [ ] `scripts/validate-inventory.sh` — syntax, required fields, uniqueness, secret-shaped keys, resolved status, and capacity reserve checks
- [ ] `tests/test-inventory.sh` — proves valid fixture acceptance and duplicate IP, unresolved placeholder, secret-shaped key, and insufficient-headroom rejection
- [ ] `tests/fixtures/invalid-inventory.json` — minimal rejection fixtures or generated mutations

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Inventory credential descriptors specify distinct service identities and minimum scopes; no values in git. [ASSUMED] |
| V3 Session Management | no | Phase 1 creates no application sessions. [VERIFIED: phase boundary] |
| V4 Access Control | yes | Document least-privilege roles for Proxmox, routers, NPM, Cloudflare, GitHub, and GHCR. [ASSUMED] |
| V5 Input Validation | yes | Reject malformed, duplicate, unresolved, or out-of-budget inventory inputs with `jq`. [ASSUMED] |
| V6 Cryptography | yes | Do not design cryptography; record SOPS/age bootstrap requirements for Phase 3. [VERIFIED: approved architecture] |

### Known Threat Patterns for the Infrastructure Contract

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret committed in inventory/docs | Information disclosure | Secret-shaped key rejection, repository secret scanning, descriptors only. [ASSUMED] |
| Over-scoped API identity | Elevation of privilege | Dedicated identity per automation boundary and minimum documented scopes. [ASSUMED] |
| Tampered IP/ownership allocation | Tampering | Git review, validator, unique identities, and explicit ownership fields. [ASSUMED] |
| Resource exhaustion after provisioning | Denial of service | Measured capacity, aggregate allocation checks, and approved reserve gate. [ASSUMED] |
| Untraceable manual prerequisite change | Repudiation | Record verification method/date and commit contract changes. [ASSUMED] |

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, and `01-CONTEXT.md` — locked topology, scope, ownership, and requirement.
- Local repository and CLI probes — implementation/test absence and available validation tools.
- [Proxmox VE Administration Guide: Start and Shutdown Order](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#qm_startup_and_shutdown) — guest ordering and delay controls.
- [Cloudflare API token documentation](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) — scoped-token capability.

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md`, and `SUMMARY.md` — previously synthesized tool, boundary, and risk research.

### Tertiary (LOW confidence)
- Proposed resource allocations, headroom threshold, startup groups, JSON shape, and validation policies are explicitly logged assumptions requiring operator validation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Phase 1 uses only locally verified tools; future tooling comes from approved project research.
- Architecture: HIGH — boundaries are locked in project context; artifact shape is an explicit assumption.
- Pitfalls: MEDIUM — repository risks are established, while thresholds and checks require local validation.

**Research date:** 2026-07-07
**Valid until:** 2026-08-06
