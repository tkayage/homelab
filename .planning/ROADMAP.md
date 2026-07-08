# Roadmap: Homelab Deploy Platform

## Overview

Milestone v1.0 builds the deployment platform from durable infrastructure boundaries upward: define capacity and networking, provision the disposable k3s cluster, establish GitOps and rebuild-safe secrets, validate local exposure, configure shared services, automate application onboarding, add public opt-in routing, and finally prove the complete system with one real application.

## Phases

- [x] **Phase 1: Infrastructure Design and Prerequisites** - Lock resource, network, identity, and bootstrap contracts before provisioning. (completed 2026-07-07)
- [x] **Phase 2: Reproducible k3s Foundation** - Provision and rebuild the single-node disposable application cluster. (completed 2026-07-07)
- [x] **Phase 3: GitOps and Secrets Bootstrap** - Establish Argo CD reconciliation, application discovery, health visibility, and rebuild-safe secrets. (completed 2026-07-07)
- [x] **Phase 4: Local DNS, Proxy, and TLS** - Deliver automatic valid-TLS LAN exposure through Mikrotik, NPM, and Traefik. (completed 2026-07-07)
- [ ] **Phase 5: Shared Stateful Services** - Provision and integrate native Postgres, Valkey, NATS, Debezium, and existing Zitadel services. (reopened 2026-07-08: artifacts committed but never deployed; deployment plan 05-05 added)
- [x] **Phase 6: Build Pipeline and Project Scaffolding** - Turn one command and a git push into a deployed private image. (completed 2026-07-08)
- [ ] **Phase 7: Opt-in Public Exposure** - Add explicit, default-deny public routing through Cloudflare and the AWS Mikrotik.
- [ ] **Phase 8: End-to-End Validation and Operations** - Prove the platform with a real app, recovery exercises, and an operator runbook.

## Phase Details

### Phase 1: Infrastructure Design and Prerequisites

**Goal**: Produce an executable infrastructure contract with validated prerequisites, resource budgets, network identities, credentials, and security boundaries.
**Depends on**: Nothing
**Requirements**: INFRA-03
**Success Criteria** (what must be TRUE):

  1. Every planned VM and LXC has an explicit CPU, memory, disk, IP/DNS name, and startup-order allocation.
  2. Proxmox, Mikrotik, NPM, Cloudflare, GitHub, and GHCR access prerequisites are documented without storing plaintext secrets.
  3. The platform boundary clearly assigns Kubernetes resources to Argo CD and external infrastructure to OpenTofu/configuration automation.
  4. The MS-01 resource budget retains explicit operating headroom.

**Plans**: 9/9 plans complete

**Wave 1**

- [x] 01-01-PLAN.md

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md
- [x] 01-03-PLAN.md

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-04-PLAN.md

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-05-PLAN.md

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-06-PLAN.md

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 01-07-PLAN.md

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 01-08-PLAN.md
- [x] 01-09-PLAN.md

### Phase 2: Reproducible k3s Foundation

**Goal**: Provision a disposable single-node k3s VM on Proxmox and demonstrate repeatable replacement.
**Depends on**: Phase 1
**Requirements**: INFRA-01, INFRA-02, INFRA-04
**Success Criteria** (what must be TRUE):

  1. Operator can provision the k3s VM from version-controlled automation without manual guest configuration.
  2. k3s and bundled Traefik start automatically and answer from the expected LAN address.
  3. No persistent application data is stored as a cluster dependency.
  4. Operator can destroy and recreate the VM while restoring cluster access from the documented bootstrap path.

**Plans**: 1/1 plans complete

- [x] 02-01-PLAN.md

### Phase 3: GitOps and Secrets Bootstrap

**Goal**: Make the platform repository the authoritative, observable, and rebuild-safe source of cluster state.
**Depends on**: Phase 2
**Requirements**: GITOPS-01, GITOPS-02, GITOPS-05, GITOPS-06
**Success Criteria** (what must be TRUE):

  1. Argo CD reconciles committed platform state and automatically discovers an application directory.
  2. A test workload becomes healthy without imperative deployment commands.
  3. Encrypted secrets decrypt during reconciliation and remain recoverable after cluster replacement.
  4. Operator can inspect health and restore an earlier known-good state through git revert.
  5. Platform-resource prune and finalizer policies prevent accidental cascading deletion.

**Plans**: 1 plan

- [x] 03-01-PLAN.md

### Phase 4: Local DNS, Proxy, and TLS

**Goal**: Give every deployed application a zero-touch LAN hostname with valid TLS.
**Depends on**: Phase 3
**Requirements**: EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-05
**Success Criteria** (what must be TRUE):

  1. A committed application hostname resolves through Mikrotik DNS and reaches the intended Traefik route through NPM.
  2. Browsers receive a valid wildcard certificate issued through Cloudflare DNS-01.
  3. Adding and deleting an application requires no manual DNS, NPM, or certificate changes.
  4. Websocket, large-request, and forwarded-client-header smoke tests pass through both proxy layers.
  5. If NPM wildcard proxying is unsuitable, a tested per-app automation fallback provides equivalent behavior.

**Plans**: 1 plan

- [x] 04-01-PLAN.md

### Phase 5: Shared Stateful Services

**Goal**: Provide durable LAN services outside k3s that applications consume through stable names and recoverable configuration.
**Depends on**: Phase 2
**Requirements**: SERV-01, SERV-02, SERV-03, SERV-04, SERV-05, SERV-06, SERV-07
**Success Criteria** (what must be TRUE):

  1. Postgres runs natively in a dedicated LXC, while Valkey, NATS/JetStream, and Debezium run with explicit limits in one dedicated Compose VM.
  2. A k3s test workload reaches every shared service through stable service names rather than hard-coded addresses.
  3. Debezium replication-slot retention and NATS storage limits are configured and observable.
  4. Applications can use the existing Zitadel deployment through its valid-TLS hostname.
  5. A Postgres backup stored away from the source LXC restores successfully into a scratch instance.

**Plans**: 4/5 plans complete

**Wave 1**

- [x] 05-01-PLAN.md
- [x] 05-02-PLAN.md
- [x] 05-03-PLAN.md
- [x] 05-04-PLAN.md

**Wave 2** *(added 2026-07-08 — plans 01-04 produced artifacts but no plan ran the deployment; see amended 05-VERIFICATION.md)*

- [~] 05-05-PLAN.md — deployed postgres-01 + services-01, Compose stack, k3s discovery live-verified (SERV-01..06). SERV-07: workstation-mediated backup; restore live-verified into a disposable scratch instance; only the off-host NAS write pending one operator action (grant workstation 10.10.30.70 rw on 10.10.40.2:/volume1/homelab-backups)

### Phase 6: Build Pipeline and Project Scaffolding

**Goal**: Make one scaffolding command plus git push build and deploy any supported application automatically.
**Depends on**: Phases 3, 4, and 5
**Requirements**: GITOPS-03, GITOPS-04, SCAF-01, SCAF-02, SCAF-03, SCAF-04, SCAF-05, SCAF-06
**Success Criteria** (what must be TRUE):

  1. Operator can scaffold a T3 or generic containerizable repository with one command and one canonical slug.
  2. A push builds a versioned image, publishes it to GHCR, updates the GitOps repository, and triggers reconciliation.
  3. A fresh namespace pulls a private GHCR image and reports meaningful readiness and liveness health.
  4. The scaffolder reports generated files, deployment health, and the expected valid-TLS URL.
  5. A generic non-T3 container can use the same deployment contract without adopting T3-specific build logic.

**Plans**: 8/8 plans complete

**Wave 1**

- [x] 06-01-PLAN.md — Dev-box tooling (sops, kustomize, actionlint) + scaffolder Go module + cobra skeleton

**Wave 2** *(blocked on Wave 1)*

- [x] 06-02-PLAN.md — slug derivation/validation + T3/non-T3 detection (TDD)
- [x] 06-03-PLAN.md — template embed/Render + T3 Dockerfile + health-route templates

**Wave 3** *(blocked on Wave 2)*

- [x] 06-04-PLAN.md — CI workflow template (two-job build→bump, actionlint)
- [x] 06-05-PLAN.md — gitops manifest templates + SOPS pull-secret + kustomize build

**Wave 4** *(blocked on Wave 3)*

- [x] 06-06-PLAN.md — gitops repo integration (clone/encrypt/commit/push, os/exec git+sops)

**Wave 5** *(blocked on Wave 4)*

- [x] 06-07-PLAN.md — CLI orchestration + SCAF-05 report (end-to-end)

**Wave 6** *(blocked on Wave 5)*

- [x] 06-08-PLAN.md — fixture validation (scaffold-verify.sh) + operator-token checkpoint

### Phase 7: Opt-in Public Exposure

**Goal**: Expose only explicitly selected applications through a default-deny public path.
**Depends on**: Phases 4 and 6
**Requirements**: PUBLIC-01, PUBLIC-02, PUBLIC-03, PUBLIC-04
**Success Criteria** (what must be TRUE):

  1. An application without the public flag is unreachable from outside the LAN.
  2. Enabling public exposure creates the required Cloudflare record and routes traffic through the AWS Mikrotik to NPM and Traefik.
  3. Disabling public exposure removes public reachability without affecting LAN access.
  4. An external scan confirms that Proxmox, Argo CD, NPM administration, Traefik dashboards, and other management surfaces are not exposed.

**Plans**: TBD

### Phase 8: End-to-End Validation and Operations

**Goal**: Validate the core value with a real application and prove routine recovery procedures.
**Depends on**: Phases 5, 6, and 7
**Requirements**: E2E-01, E2E-02, E2E-03, E2E-04, E2E-05
**Success Criteria** (what must be TRUE):

  1. One real application goes from git push to a healthy valid-TLS URL without manual deployment wiring.
  2. The application connects to shared Postgres and authenticates through existing Zitadel.
  3. Operator observes a failed deployment and restores service through git revert.
  4. The complete platform returns to service after an MS-01 restart with correct dependency ordering.
  5. A tested runbook covers bootstrap, app onboarding, diagnosis, rollback, backup, restore, and cluster replacement.

**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Infrastructure Design and Prerequisites | 9/9 | Complete    | 2026-07-07 |
| 2. Reproducible k3s Foundation | 1/1 | Complete    | 2026-07-07 |
| 3. GitOps and Secrets Bootstrap | 1/1 | Complete | 2026-07-07 |
| 4. Local DNS, Proxy, and TLS | 1/1 | Complete | 2026-07-07 |
| 5. Shared Stateful Services | 5/5 | In progress (SERV-07 pending) | - |
| 6. Build Pipeline and Project Scaffolding | 8/8 | Complete   | 2026-07-08 |
| 7. Opt-in Public Exposure | 0/TBD | Not started | - |
| 8. End-to-End Validation and Operations | 0/TBD | Not started | - |
