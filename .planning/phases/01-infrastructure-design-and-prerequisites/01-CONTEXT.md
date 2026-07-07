# Phase 1: Infrastructure Design and Prerequisites - Context

**Gathered:** 2026-07-07
**Status:** Ready for planning
**Mode:** Auto-generated (pure infrastructure phase)

<domain>
## Phase Boundary

Produce an executable infrastructure contract with validated prerequisites, resource budgets, network identities, credentials, and security boundaries. This phase defines and validates the inputs used by later provisioning phases; it does not provision production infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Codex's Discretion
- All implementation choices are at Codex's discretion for this pure infrastructure phase.
- Preserve the approved architecture: disposable single-node k3s VM, one native-service LXC per durable service, existing Zitadel retained, GitOps ownership limited to Kubernetes resources, and local-first exposure.
- Prefer machine-readable inventories with documented placeholder values where environment-specific facts are unavailable.
- Never commit credentials or secret values; document names, scopes, storage locations, and acquisition checks only.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.planning/PROJECT.md` defines the topology, constraints, and non-negotiable platform boundaries.
- `.planning/REQUIREMENTS.md` maps Phase 1 to INFRA-03.
- `.planning/research/` contains stack, feature, architecture, and pitfall findings that establish the initial sizing and ownership model.

### Established Patterns
- This repository currently contains planning artifacts rather than an implementation codebase.
- Infrastructure will be version controlled and secret-free, with durable state outside k3s.

### Integration Points
- Phase 2 consumes the VM/network/bootstrap contract.
- Phase 5 consumes the LXC sizing, addresses, DNS names, and startup ordering.
- Phases 3, 4, 6, and 7 consume credential-scope and system-ownership definitions.

</code_context>

<specifics>
## Specific Ideas

Use explicit assumption markers and validation checklists for unknown site-specific values such as Proxmox version, bridge name, VLAN/subnet, storage pool, MS-01 capacity, domain, and existing service addresses.

</specifics>

<deferred>
## Deferred Ideas

Actual provisioning, credential creation, router changes, and external-service mutations belong to their respective later phases.

</deferred>
