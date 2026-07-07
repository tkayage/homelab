# Phase 2: Reproducible k3s Foundation - Context

**Gathered:** 2026-07-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Provision the Phase 1-defined disposable single-node `k3s-01` VM on Proxmox through version-controlled automation, bootstrap k3s and bundled Traefik without manual guest configuration, validate LAN readiness, and prove repeatable destroy/recreate recovery. GitOps workloads, application persistence, shared services, DNS/proxy automation, and public exposure remain later-phase work.

</domain>

<decisions>
## Implementation Decisions

### Provisioning Contract
- Use OpenTofu with the Proxmox provider as the provisioning engine.
- Use cloud-init to install and configure k3s non-interactively.
- Use a version-pinned Ubuntu LTS cloud image rather than an unpinned or custom image.
- Keep OpenTofu state local, permission-restricted, excluded from git, and encrypted at rest by the operator environment.

### Cluster Bootstrap and Access
- Pin an explicit k3s version and verify downloaded installation material before execution.
- Keep bundled Traefik enabled and validate its installed version and configuration.
- Retrieve kubeconfig after provisioning, rewrite its server to the stable LAN identity, and store it locally with restrictive permissions.
- Require node Ready, healthy system pods, responding Traefik, and the expected LAN address before declaring success.

### Replacement and Durability
- Prove replacement through an automated destroy/recreate exercise using the same version-controlled inputs.
- Reject local-path application persistence; the cluster may retain only disposable system state.
- Reuse VMID `122`, IPv4 `10.10.30.102`, and DNS `k3s.app.kayage.co` from the Phase 1 contract.
- Fail closed on image, provisioning, bootstrap, or readiness errors while retaining secret-free diagnostics.

### the agent's Discretion
- Exact OpenTofu module layout, helper-script boundaries, validation implementation, retry/backoff values, and documentation organization may follow established infrastructure-as-code conventions.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `infrastructure/inventory.json` is the canonical source for VMID, allocation, network, startup, ownership, and capacity facts.
- `scripts/validate-inventory.sh` and `tests/test-inventory.sh` establish fail-closed Bash/jq validation and mutation-test patterns.
- Read-only credentials are stored outside git under `/home/tonny/.config/homelab/`.

### Established Patterns
- Environment observations are source-dated and contain no authentication material.
- Automation validates canonical inventory rather than duplicating mutable values silently.
- Each executable contract has positive validation plus focused negative cases.

### Integration Points
- OpenTofu must consume or cross-check the `k3s-01` contract in `infrastructure/inventory.json`.
- Proxmox API access uses the external credential file and must never persist token values in state, plans, logs, or summaries.
- Phase 3 will consume the resulting cluster endpoint and kubeconfig bootstrap path.

</code_context>

<specifics>
## Specific Ideas

- Preserve the exact Phase 1 identity and allocation contract for `k3s-01`.
- Replacement evidence must demonstrate actual repeatability rather than only documenting commands.
- The cluster is disposable by design; durable application data belongs outside k3s.

</specifics>

<deferred>
## Deferred Ideas

- Argo CD, encrypted cluster secrets, and application reconciliation belong to Phase 3.
- LAN DNS, NPM routing, and TLS automation belong to Phase 4.
- Shared stateful services belong to Phase 5.

</deferred>
