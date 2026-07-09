---
phase: 07-opt-in-public-exposure
status: discussed
date: 2026-07-09
---

# Phase 7: Opt-in Public Exposure - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver explicit, default-deny public exposure for selected applications without changing the Phase 4 LAN exposure rail. This phase owns the public opt-in contract, public DNS/routing automation, enable/disable lifecycle proof, and external scan evidence that management surfaces remain private. It does not replace the existing LAN wildcard NPM -> Traefik path, does not move TLS ownership out of NPM, and does not deploy the final validation application from Phase 8.

</domain>

<decisions>
## Implementation Decisions

### Public Exposure Contract
- Public exposure is default-deny: an application without an explicit public flag remains LAN-only.
- The opt-in marker belongs in the app's GitOps manifest set so Git remains the source of truth.
- The public marker must be obvious in review, preferably a small generated file or annotation keyed by slug, not an implicit hostname convention.
- Disabling the marker must remove public reachability while preserving LAN access through the existing `*.app.kayage.co` NPM wildcard rail.

### Routing and DNS
- Reuse Phase 4's LAN path after traffic reaches the home edge: public client -> Cloudflare DNS -> AWS Mikrotik/CHR -> home NPM -> k3s Traefik -> app Service.
- Public Cloudflare records are per-app opt-in records, not a public wildcard for `*.app.kayage.co`.
- Automation must continue to assert that no public wildcard record exists for `*.app.kayage.co`.
- If live AWS Mikrotik/CHR credentials or state are unavailable, implement the contract and offline/live-safe validation commands, then mark only the external reachability proof as manual/deferred.

### Security Boundaries
- Administrative surfaces are permanently denylisted: Proxmox, Argo CD, NPM administration, Traefik dashboards, Mikrotik admin endpoints, service VMs/LXCs, and shared databases.
- Public exposure automation may manage only labeled platform-owned Cloudflare records and router/NAT entries.
- No Cloudflare, Mikrotik, NPM, or AWS credentials may be committed; scripts load from `/home/tonny/.config/homelab/*.env` like prior phases.
- External scan evidence is required before closing the phase.

### Operator Ergonomics
- Keep the workflow script-driven, matching `scripts/local-edge.sh`: `preflight`, `apply`, `status`, and proof commands.
- Prefer idempotent reconcile behavior and stable resource IDs over one-shot imperative changes.
- Report exactly what was exposed, what stayed private, and the command to disable exposure.
- The scaffolder may gain public-exposure metadata generation if needed, but existing scaffolded apps must remain LAN-only by default.

### the agent's Discretion
- Choose the smallest implementation surface that can prove PUBLIC-01 through PUBLIC-04.
- Use existing tools already present in the repo where practical: Bash, jq, curl, kubectl, git, Cloudflare API calls, and the existing GitOps worktree.
- Add tests around manifest generation and fail-closed policy even if live public routing must be manually verified.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/local-edge.sh` already handles credential loading for Mikrotik, NPM, Cloudflare, GitHub, kubeconfig, NPM login, Cloudflare token verification, and asserts that no public wildcard DNS record exists.
- `infrastructure/edge/local-edge.json` defines the LAN suffix `app.kayage.co`, NPM IP `10.10.30.237`, and Traefik forward target `10.10.30.102`.
- `scaffold/internal/templates/files/gitops/ingress.yaml.tmpl` emits the per-app Ingress used by Traefik.
- `scripts/scaffold-verify.sh` provides a pattern for offline fixture verification without using real external credentials.

### Established Patterns
- Phase scripts use Bash with `set -euo pipefail`, `ROOT` resolution, `die`/`need` helpers, credential env files outside git, and explicit subcommands.
- External state reconciliation should be idempotent and conflict-aware; Phase 4 only manages entries labeled with the platform owner marker.
- GitOps remains the deployment source of truth; direct cluster changes are only validation/proof steps unless they bootstrap external controllers.

### Integration Points
- Phase 7 should extend the edge contract under `infrastructure/edge/` and scripts under `scripts/`.
- Public opt-in metadata must integrate with the scaffolded GitOps app directory under `apps/<slug>/` and the generated Ingress contract.
- Verification should use Cloudflare API checks for public records and an external scan/probe from outside the LAN path when available.

</code_context>

<specifics>
## Specific Ideas

- Approved conservative default: public exposure must be opt-in per app; no flag means LAN-only.
- Keep Phase 4's LAN wildcard NPM path intact.
- Public records should be per-host, not wildcard.
- Denylist management surfaces explicitly and scan them before closure.

</specifics>

<deferred>
## Deferred Ideas

- Phase 8 will deploy the real validation application through the completed platform and prove the full app workflow.
- Broader dashboarding, notifications, and decommission automation remain future DX/OPS requirements.

</deferred>
