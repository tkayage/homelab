# Homelab Deploy Platform

## What This Is

A reusable deployment platform and workflow for a personal homelab. Apps are built on a dev server (VS Code + t3 code); a scaffolding step wires each project into a GitOps pipeline so that every git push builds a container image and deploys it to a k3s cluster running on a Proxmox MS-01 — with DNS, reverse proxy, and TLS provisioned automatically per app. Built by and for a solo developer who ships many projects and wants deployment to be a solved problem.

## Core Value

Push to git → app is live at `myapp.yourdomain.com` with valid TLS, no manual wiring. Deployment must be a zero-touch, repeatable step for every new project.

## Current Milestone: v1.0 End-to-End Homelab Deployment

**Goal:** A git push builds and publishes an app image, deploys it to k3s through GitOps, and exposes it at a valid-TLS hostname without manual wiring.

**Target features:**
- Provision a single-node k3s VM on the Proxmox MS-01
- Deploy GitOps and integrate GHCR image builds and pulls
- Provision a dedicated Postgres LXC and a dedicated Compose VM for Valkey, Debezium, and NATS/JetStream
- Integrate the existing Zitadel LXC and LAN-accessible shared services
- Automate local DNS, Nginx Proxy Manager routing, and Cloudflare DNS-01 TLS
- Support explicit opt-in public exposure through the AWS Mikrotik
- Provide reusable per-project deployment scaffolding
- Deploy one real application through the complete pipeline

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] k3s cluster provisioned as a single VM on the Proxmox MS-01 (apps only — ephemeral, rebuildable)
- [ ] GitOps engine (ArgoCD or Flux) running in the cluster; git push triggers deployment
- [ ] Container images built and pushed to GHCR; cluster pulls from GHCR
- [ ] Per-project scaffolding tool: run once in any project to generate manifests/pipeline config and register it with the GitOps repo
- [ ] Automatic local exposure (default): Mikrotik LAN DNS static entry + Nginx Proxy Manager proxy host + valid TLS cert (Cloudflare DNS-01) created per app
- [ ] Opt-in public exposure: Cloudflare DNS record pointing at the AWS Mikrotik public IP, traffic forwarded downstream to NPM → k3s ingress
- [ ] Shared services provisioned on Proxmox: Postgres in a dedicated native-service LXC; Valkey, Debezium, and NATS + JetStream in one dedicated Docker Compose VM
- [ ] Existing Zitadel LXC integrated as-is (not re-provisioned) — apps can use it for auth
- [ ] Apps in k3s reach shared services over the LAN
- [ ] One real app deployed end-to-end through the pipeline (the success gate for v1)

### Out of Scope

- Multi-node / HA k3s — single MS-01; multi-VM on one host adds complexity without real hardware redundancy; revisit if nodes are added
- Stateful services inside k3s (operators like CloudNativePG) — state lives in LXCs so the cluster stays disposable
- Docker-in-LXC for shared services — Docker workloads use a dedicated VM to avoid nesting/AppArmor fragility
- Self-hosted container registry — GHCR is free and removes infra to run; revisit if egress/privacy becomes an issue
- Full-platform disaster-recovery reproducibility — v1 success is one app live end-to-end; polish and full rebuild-from-code come after
- Monitoring/observability stack — not discussed for v1; capture as a future milestone
- CLI-driven imperative deploys — GitOps is the deployment interface; scaffolding is the only per-project manual step

## Context

**Existing environment:**
- Dev server with VS Code and t3 code where all apps and services are built
- Proxmox VE on a single Minisforum MS-01 (the homelab server)
- Zitadel already running in an LXC container on Proxmox — the only shared service that exists today
- Nginx Proxy Manager on the local network (reverse proxy for LAN services)
- Local Mikrotik router handles LAN DNS (static DNS entries)
- AWS-hosted Mikrotik router (CHR) with a public IP that can receive internet traffic and forward it downstream to NPM
- Domain managed on Cloudflare

**Routing model:**
- Default (local-only): split DNS — Mikrotik LAN DNS resolves `myapp.domain.com` to NPM, NPM proxies to k3s ingress; TLS via Cloudflare DNS-01 so certs are valid without public exposure
- Opt-in (public): Cloudflare DNS → AWS Mikrotik public IP → tunnel/forward to home network → NPM → k3s ingress

**Apps:** primarily T3-stack (TypeScript) web apps, but the pipeline should be app-agnostic (anything containerizable).

## Constraints

- **Hardware**: Single Minisforum MS-01 — one Proxmox node; no hardware redundancy, topology must not pretend otherwise
- **Tech stack**: k3s for app workloads; LXC for stateful shared services; GHCR for images; Cloudflare for DNS/certs; NPM as reverse proxy; Mikrotik for LAN DNS and public ingress — all already chosen or in place
- **Dependencies**: Existing Zitadel LXC must be integrated, not replaced
- **Security**: Local-first by default — apps are only exposed publicly by explicit opt-in
- **Solo operator**: One person builds and runs everything — favor simple, low-maintenance choices over resume-driven architecture

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GitOps (ArgoCD/Flux) over CLI or CI-push deploys | Git as source of truth; scaffold once, every push deploys | — Pending |
| Apps in k3s, state outside k3s | Cluster stays disposable; rebuilding k3s never risks data | — Pending |
| Dedicated Postgres LXC; shared Compose VM for Valkey, Debezium, and NATS | Isolate the durable database while consolidating supporting services without Docker-in-LXC | — Pending |
| Docker only in a dedicated VM, never Docker-in-LXC | Avoids nesting/AppArmor quirks while retaining Compose operational simplicity | — Pending |
| GHCR for container images | Free, zero infra to run, integrates with git hosting | — Pending |
| Single k3s VM on the one MS-01 | Multi-VM on one host = complexity without real redundancy | — Pending |
| Split DNS: Mikrotik static entries for LAN, Cloudflare for public | Local apps resolve locally, no hostname leakage; public opt-in via AWS Mikrotik | — Pending |
| Cloudflare DNS-01 for TLS certs | Valid certs for local-only apps without opening ports | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-07 after starting milestone v1.0*
