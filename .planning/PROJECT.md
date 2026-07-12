# Homelab Deploy Platform

## What This Is

A reusable deployment platform and workflow for a personal homelab. Apps are built on a dev server (VS Code + t3 code); a scaffolding step wires each project into a GitOps pipeline so that every git push builds a container image and deploys it to a k3s cluster running on a Proxmox MS-01 — with DNS, reverse proxy, and TLS provisioned automatically per app. Built by and for a solo developer who ships many projects and wants deployment to be a solved problem.

## Core Value

Push to git → app is live at `myapp.yourdomain.com` with valid TLS, no manual wiring. Deployment must be a zero-touch, repeatable step for every new project.

## Current Milestone: v1.1 Scaffolder CLI Service

**Goal:** Make the homelab scaffolder a dev-server CLI binary that can onboard and update containerized services through the GitOps pipeline.

**Target features:**
- Install and run the scaffolder as a CLI binary on the dev server.
- Replace T3 detection with Dockerfile-first detection.
- Offer to generate a Dockerfile when a project does not already have one.
- Support updating existing services, not just creating new ones.
- Add or update non-secret environment variables for existing services.
- Add or update encrypted GitOps secrets for existing services.
- Commit updates through the normal GitOps repository flow.

## Requirements

### Validated

- [x] Phase 1 infrastructure contract defines explicit guest allocations, measured operating headroom, verified prerequisites, and automation ownership boundaries. — Validated in Phase 1: Infrastructure Design and Prerequisites
- [x] k3s cluster is provisioned as a single disposable VM on the Proxmox MS-01. — Validated in Phase 2: Reproducible k3s Foundation
- [x] Argo CD reconciles the platform GitOps repository and deploys discovered app directories. — Validated in Phase 3: GitOps and Secrets Bootstrap
- [x] Local LAN exposure uses Mikrotik DNS, NPM, Traefik, and Cloudflare DNS-01 TLS. — Validated in Phase 4: Local DNS, Proxy, and TLS
- [x] Shared services run outside k3s: Postgres in a native LXC, Valkey/NATS/Debezium in a Compose VM, and Zitadel integrated as-is. — Validated in Phase 5: Shared Stateful Services
- [x] Project scaffolding builds/publishes GHCR images, writes GitOps manifests, and supports T3 or generic containerizable apps. — Validated in Phase 6: Build Pipeline and Project Scaffolding
- [x] Public exposure is default-deny and requires explicit per-app opt-in metadata. — Validated in Phase 7: Opt-in Public Exposure
- [x] One real app (`/home/tonny/fintrack`) is deployed end to end as a healthy GitOps-managed daemon with rollback proof. — Validated in Phase 8: End-to-End Validation and Operations

### Active

- [ ] Scaffolder is installed and runnable as a CLI binary on the dev server.
- [ ] Scaffolder uses Dockerfile-first project detection instead of T3-stack detection.
- [ ] Scaffolder offers to generate a Dockerfile when one is missing.
- [ ] Scaffolder can update existing GitOps-managed services.
- [ ] Scaffolder can add or update non-secret environment variables for existing services.
- [ ] Scaffolder can add or update encrypted GitOps secrets for existing services.
- [ ] Scaffolder commits service configuration changes through the normal GitOps repository flow.

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

**Deferred operations:**
- MS-01 restart recovery should be verified during an operator-approved maintenance window.
- A future web validation app should prove valid-TLS URL, Postgres, and Zitadel integration end to end.

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
| Apps in k3s, state outside k3s | Cluster stays disposable; rebuilding k3s never risks data | Validated in Phase 1 |
| Dedicated Postgres LXC; shared Compose VM for Valkey, Debezium, and NATS | Isolate the durable database while consolidating supporting services without Docker-in-LXC | Validated in Phase 1 |
| Docker only in a dedicated VM, never Docker-in-LXC | Avoids nesting/AppArmor quirks while retaining Compose operational simplicity | Validated in Phase 1 |
| GHCR for container images | Free, zero infra to run, integrates with git hosting | Validated in Phase 8 |
| Single k3s VM on the one MS-01 | Multi-VM on one host = complexity without real redundancy | Validated in Phase 2 |
| Split DNS: Mikrotik static entries for LAN, Cloudflare for public | Local apps resolve locally, no hostname leakage; public opt-in via AWS Mikrotik | Validated in Phases 4 and 7 |
| Cloudflare DNS-01 for TLS certs | Valid certs for local-only apps without opening ports | Validated in Phase 4 |
| MS-01 restart recovery deferred from v1.0 closure | Rebooting the physical host is intentionally disruptive and should run during an operator-approved maintenance window | — Pending future operations |

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
*Last updated: 2026-07-12 after starting v1.1 Scaffolder CLI Service*
