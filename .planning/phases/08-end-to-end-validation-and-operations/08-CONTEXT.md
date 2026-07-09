---
phase: 08-end-to-end-validation-and-operations
status: discussed
date: 2026-07-09
---

# Phase 8: End-to-End Validation and Operations - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Deploy the real project `fintrack` from `/home/tonny/fintrack` through the homelab platform end to end. `fintrack` is an outbound-only daemon that consumes Cloudflare queue/R2 inputs, runs statement parsers, calls the Sure API, sends alerts, and stores dedupe state in SQLite. It intentionally has no HTTP listener, no Service, no Ingress, no valid-TLS URL, no Postgres dependency, and no Zitadel authentication flow.

This phase proves the platform can deploy a real private workload with GitOps, encrypted configuration, private image pulling, operator visibility, rollback, and recovery evidence. The original Phase 8 web-app checks are adapted for this selected service: health is a running daemon and successful startup/log evidence, not an HTTP URL; shared-state proof is the persistent dedupe volume and external API/queue connectivity, not Postgres; authentication proof is not applicable because the app has no user-facing auth surface.

</domain>

<decisions>
## Implementation Decisions

### Selected Application
- Use project name and slug `fintrack`.
- Source repository is `/home/tonny/fintrack`.
- Build the image from `/home/tonny/fintrack/deploy/Dockerfile`.
- Preserve the app's documented security contract: do not add an inbound health server, Kubernetes Service, Ingress, Traefik route, or public exposure metadata.

### Deployment Shape
- Deploy as a Kubernetes `Deployment` with one replica in namespace `fintrack`.
- Use a persistent volume mounted at `/data` for SQLite dedupe state.
- Mount `allowlist.json` as a read-only Secret or ConfigMap-backed file at `/config/allowlist.json`.
- Provide runtime environment through a SOPS-encrypted Kubernetes Secret in GitOps.
- Register the workload under `.local/gitops-homelab/apps/fintrack/` so the existing ApplicationSet discovers it.

### Image and GitOps
- Prefer GHCR image `ghcr.io/tkayage/fintrack:<tag>` when credentials are available.
- If no application Git remote exists, build and push locally instead of inventing a remote. Record this as a validation-app deviation from the Phase 6 "git push" path.
- Pin the GitOps Deployment to the exact built tag or digest used for verification.
- Do not commit plaintext secrets or generated secret manifests outside SOPS encryption.

### Verification Adaptation
- E2E-01 is satisfied for this selected daemon by GitOps discovery, private image pull, and healthy running pod evidence, not by a valid-TLS URL.
- E2E-02 is not directly applicable to `fintrack`; record the selected-app mismatch instead of adding fake Postgres or Zitadel dependencies.
- E2E-03 remains in scope: prove a failed deployment is visible in Argo/kubectl and recover through git revert or GitOps rollback.
- E2E-04 remains in scope: run or document the MS-01 restart dependency-order exercise with live checks where possible.
- E2E-05 remains in scope: write the operator runbook for bootstrap, onboarding, diagnosis, rollback, backup/restore, and cluster replacement, including the fintrack daemon deployment path.

### Secrets and Blockers
- Required daemon configuration is expected from operator-owned files, environment variables, or external secret stores. If real Cloudflare/Sure credentials and `allowlist.json` are absent, fail closed: deploy manifests may be prepared, but do not fabricate working credentials.
- Any credential discovery must check file presence and variable names without printing secret values.

</decisions>

<code_context>
## Fintrack Code Insights

### Application Behavior
- `daemon/main.go` requires Cloudflare queue/R2 configuration, Sure API configuration, parser paths, dedupe DB path, alert email configuration, and an allowlist source.
- Required environment includes `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `CF_QUEUE_ID`, `SURE_URL`, `SURE_API_KEY`, `PARSERS_DIR`, `DEDUPE_DB_PATH`, `ALERT_FROM`, `ALERT_TO`, and either `ALLOWLIST_FILE` or `ALLOWLIST`.
- The Dockerfile defaults `DEDUPE_DB_PATH=/data/dedupe.db` and `ALLOWLIST_FILE=/config/allowlist.json`.
- `deploy/docker-compose.yml` confirms the daemon expects no ports and persists only `/data`.

### Homelab Integration Points
- The platform ApplicationSet discovers `apps/*` in `.local/gitops-homelab`.
- SOPS-encrypted `*.enc.yaml` files are supported by the existing GitOps plugin.
- Cluster access is through `KUBECONFIG=.local/kubeconfig-k3s-01`.
- GHCR private image pulls are already supported by Phase 6 pull-secret generation patterns.
- Public exposure from Phase 7 is explicitly out of scope for this daemon.

</code_context>

<specifics>
## Specific Ideas

- Use a Kubernetes Secret with two entries: `.env` style values as discrete environment keys, and `allowlist.json` as a mounted file.
- Use a PVC for `/data` even though the k3s node is disposable; this preserves daemon state across pod restarts and makes the selected persistence tradeoff explicit.
- Use a rollout plus recent pod logs as the primary live health proof.
- Add runbook sections that distinguish web workloads from outbound-only daemon workloads.

</specifics>

<deferred>
## Deferred Ideas

- A future app that uses Postgres, Zitadel, and a valid-TLS route can exercise the web-specific E2E-01 and E2E-02 criteria without weakening fintrack's no-inbound security model.
- Automated OIDC client provisioning and app-specific database provisioning remain future DX items.

</deferred>
