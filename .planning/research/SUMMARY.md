# Project Research Summary

**Project:** Homelab Deploy Platform
**Domain:** GitOps-based homelab deployment platform
**Researched:** 2026-07-07
**Confidence:** MEDIUM

## Executive Summary

The platform should use a disposable single-node k3s VM for applications, keep durable services in dedicated Proxmox LXCs, and use Git as the deployment interface. The recommended control plane is OpenTofu plus the bpg/proxmox provider for infrastructure, Argo CD with an ApplicationSet for GitOps, GitHub Actions and GHCR for images, and SOPS with age for rebuild-safe secrets.

The shortest path to zero-touch local exposure is wildcard-first: one Mikrotik LAN DNS rule, one Nginx Proxy Manager wildcard proxy host, and one wildcard certificate obtained through Cloudflare DNS-01. This must be validated early because NPM wildcard proxy behavior is the principal uncertainty; per-app API automation remains the fallback. Public exposure should remain explicit and additive through Cloudflare DNS plus the AWS Mikrotik path.

The main risks are bootstrap circular dependencies, unsafe Argo CD pruning, secret loss during cluster rebuilds, double-proxy failures, under-sized LXCs, Debezium WAL growth, and accidentally exposing administrative surfaces. The roadmap should prove each infrastructure rail incrementally and keep the final success gate focused on one real application deployed from git push to valid-TLS URL.

## Key Findings

### Recommended Stack

**Core technologies:**
- k3s with bundled Traefik: disposable application cluster and ingress
- Argo CD with ApplicationSet: GitOps reconciliation and automatic app discovery
- OpenTofu with bpg/proxmox: reproducible VM and LXC provisioning
- GitHub Actions with GHCR: container build and registry pipeline
- SOPS with age and KSOPS: secrets that survive cluster replacement
- Nginx Proxy Manager with Cloudflare DNS-01: edge TLS termination
- TypeScript scaffolding CLI and shared Helm app chart: consistent app onboarding

### Expected Features

**Must have:**
- Git push builds, publishes, and deploys an image
- GitOps auto-sync, health visibility, self-heal, prune, and git-revert rollback
- Valid TLS and hostname routing without per-app manual wiring
- Safe secrets, private GHCR pulls, and application health probes
- App connectivity to Postgres, Valkey, Debezium, NATS/JetStream, and Zitadel
- Local-only exposure by default and explicit public opt-in
- One-command scaffolding and one real end-to-end application

**Defer until after v1 validation:**
- Automated per-app database/user creation
- Notifications, dashboard discovery, teardown automation, and Renovate
- Automated Zitadel client provisioning, staging overlays, observability, and preview environments

### Architecture Approach

Use one GitOps platform repository for cluster add-ons, shared-service endpoints, a shared application chart, and per-app values. Argo CD watches that repository and discovers `apps/*`; individual app repositories contain source, Dockerfiles, and CI workflows that publish to GHCR and update their image tag in the platform repository. Argo CD owns Kubernetes resources only; OpenTofu and configuration automation own Proxmox, LXCs, routers, and NPM.

### Critical Pitfalls

1. **Bootstrap circular dependency** — keep a minimal, documented bootstrap path and test a full k3s rebuild.
2. **Unsafe Argo CD prune/finalizers** — use conservative sync policies for platform resources and test deletion on leaf apps.
3. **Secrets bound to the disposable cluster** — use SOPS+age and maintain an offline age-key backup.
4. **Wildcard/double-proxy edge failures** — spike NPM wildcard routing and test websockets, uploads, and forwarded headers.
5. **Stateful-service resource and recovery failures** — define RAM/disk limits, control Debezium WAL growth, and verify off-host Postgres restores.
6. **Public exposure leaks** — default-deny the AWS CHR path and externally verify that administrative interfaces remain unreachable.

## Implications for Roadmap

### Phase 1: Infrastructure Foundation
Provision the k3s VM and service LXCs with explicit resource budgets, network identity, and repeatable configuration.

### Phase 2: GitOps and Secrets Bootstrap
Create the platform repository, install Argo CD and ApplicationSet, establish SOPS+age, and prove reconciliation with a test workload.

### Phase 3: Local Exposure Spine
Validate wildcard Mikrotik DNS, NPM wildcard routing, Cloudflare DNS-01 TLS, and Traefik forwarding; implement per-app fallback automation if the spike fails.

### Phase 4: Shared Services
Configure Postgres natively in a dedicated LXC and configure Valkey, NATS/JetStream, and Debezium in a dedicated Compose VM; integrate Zitadel and expose stable LAN service endpoints to k3s.

### Phase 5: Build Pipeline and Scaffolding
Build the shared app chart and TypeScript scaffolder, generate CI/GHCR integration, and prove that a push deploys a private image automatically.

### Phase 6: Public Opt-in Exposure
Configure the AWS CHR path and annotation/flag-driven Cloudflare records with default-deny verification.

### Phase 7: End-to-End Validation
Deploy one real application using shared services and Zitadel, exercise rollback and restart behavior, and document the operational runbook.

### Phase Ordering Rationale

Infrastructure precedes GitOps; GitOps precedes exposure and app automation; shared services and public networking can progress after the control plane exists; scaffolding is implemented only after its target conventions work manually. The final phase validates the system as a whole rather than introducing new architecture.

### Research Flags

- Local exposure needs a short NPM wildcard-host compatibility spike.
- GitOps bootstrap needs focused KSOPS and Argo CD self-management research.
- Shared services need explicit Debezium WAL, JetStream storage, and Postgres recovery validation.
- Public exposure needs current RouterOS/WireGuard and firewall-rule validation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Versions and primary projects were checked, but integrations require local validation |
| Features | MEDIUM | Strong convergence across homelab GitOps and self-hosted PaaS patterns |
| Architecture | MEDIUM | Boundaries are established; wildcard NPM behavior remains uncertain |
| Pitfalls | MEDIUM | Supported by official documentation and multiple practitioner reports |

**Overall confidence:** MEDIUM

### Gaps to Address

- Validate wildcard NPM proxy-host routing before committing to the simplified local exposure design.
- Confirm exact Proxmox version, network ranges, VM/LXC templates, and resource capacity during phase planning.
- Decide and test the minimal Argo CD/KSOPS bootstrap mechanism.
- Confirm GitHub repository ownership and cross-repository write credentials for CI tag updates.

## Sources

Detailed citations and version evidence are retained in `STACK.md`, `FEATURES.md`, `ARCHITECTURE.md`, and `PITFALLS.md`.

---
*Research completed: 2026-07-07*
*Ready for roadmap: yes*
