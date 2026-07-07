# Phase 3: GitOps and Secrets Bootstrap - Context

**Gathered:** 2026-07-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish Argo CD as the reconciler for committed cluster state, automatically discover application directories, prove a test workload and git-revert rollback, and make encrypted secrets recoverable after replacement. DNS/proxy/TLS, shared services, build pipelines, and public exposure remain later phases.

</domain>

<decisions>
## Implementation Decisions

### GitOps Topology
- Use Argo CD.
- Discover workloads with an ApplicationSet Git directory generator.
- Organize cluster services under `platform/` and workloads under `apps/*/`.
- Use automated sync with self-heal and guarded pruning.

### Secret Recovery
- Encrypt committed secrets with SOPS and age.
- Decrypt through an Argo CD repo-server plugin with the age key mounted from bootstrap state.
- Store the recovery key in the external operator credential directory, never git or cluster-only storage.
- After replacement, bootstrap the age key before allowing Argo CD reconciliation.

### Safety and Operations
- Disable pruning for platform roots; enable it only for explicitly safe application resources.
- Preserve resources when Applications are deleted and require explicit finalizer opt-in.
- Provide CLI-first health status plus local Argo CD UI port-forward access.
- Prove rollback with a controlled workload commit followed by `git revert` and observed reconciliation.

### the agent's Discretion
- Exact Argo CD pinned version, namespace/resource naming, CMP sidecar implementation, test workload, status-script output, and bootstrap command layout may follow current official patterns.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 2 provides `.local/kubeconfig-k3s-01`, `scripts/k3s-platform.sh`, and a healthy disposable cluster.
- External GitHub credentials live under `/home/tonny/.config/homelab/github.env`.
- Secret and generated runtime artifacts are already excluded through `.gitignore`.

### Established Patterns
- Versions and downloads are pinned and checksum verified.
- External credentials never enter git, plans, logs, or summaries.
- Lifecycle automation is fail-closed and backed by static plus live tests.

### Integration Points
- Reconciliation targets the private `tkayage/gitops-homelab` repository on `main`.
- Phase 4 will consume Argo-managed ingress resources.
- Replacement recovery begins after Phase 2 restores kubeconfig.

</code_context>

<specifics>
## Specific Ideas

- Git remains the authoritative desired-state and rollback interface.
- Platform deletion must not cascade into protected resources by default.

</specifics>

<deferred>
## Deferred Ideas

- Automated image updates and scaffolding belong to Phase 6.
- DNS, proxy, TLS, and public routes belong to Phases 4 and 7.

</deferred>
