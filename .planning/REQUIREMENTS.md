# Requirements: Homelab Deploy Platform

**Defined:** 2026-07-07
**Milestone:** v1.0 End-to-End Homelab Deployment
**Core Value:** Push to git → app is live at `myapp.yourdomain.com` with valid TLS, no manual wiring.

## v1.0 Requirements

### Foundation

- [ ] **INFRA-01**: Operator can reproducibly provision a single-node k3s VM on Proxmox.
- [ ] **INFRA-02**: k3s starts automatically and remains disposable without risking persistent data.
- [ ] **INFRA-03**: Infrastructure configuration defines explicit network, CPU, memory, and storage allocations.
- [ ] **INFRA-04**: Operator can rebuild the k3s VM from documented automation.

### GitOps and Images

- [ ] **GITOPS-01**: Argo CD reconciles the platform repository automatically.
- [ ] **GITOPS-02**: Adding an app directory automatically registers and deploys the application.
- [ ] **GITOPS-03**: Application repositories build and publish versioned images to GHCR on push.
- [ ] **GITOPS-04**: CI updates the GitOps image reference and triggers deployment without manual cluster commands.
- [ ] **GITOPS-05**: Secrets remain encrypted in git and recoverable after cluster replacement.
- [ ] **GITOPS-06**: Operator can inspect deployment health and roll back through git revert.

### Local Exposure

- [ ] **EDGE-01**: Local clients resolve application hostnames to NPM through Mikrotik DNS.
- [ ] **EDGE-02**: NPM terminates valid TLS using a Cloudflare DNS-01 wildcard certificate.
- [ ] **EDGE-03**: NPM and Traefik route each hostname to the correct application.
- [ ] **EDGE-04**: Exposure supports websockets, large requests, and correct forwarded headers.
- [ ] **EDGE-05**: Adding or removing an application requires no manual DNS, proxy, or certificate wiring.

### Shared Services

- [ ] **SERV-01**: Postgres runs as a native service in a dedicated Proxmox LXC.
- [ ] **SERV-02**: Valkey or Redis runs as a native service in a dedicated LXC.
- [ ] **SERV-03**: NATS with JetStream runs as a native service in a dedicated LXC with bounded storage.
- [ ] **SERV-04**: Debezium runs in a dedicated LXC with controlled replication-slot WAL growth.
- [ ] **SERV-05**: k3s applications reach shared services through stable LAN names.
- [ ] **SERV-06**: Applications integrate with the existing Zitadel deployment without replacing it.
- [ ] **SERV-07**: Postgres has a verified off-host backup and restore procedure.

### Scaffolding

- [ ] **SCAF-01**: Operator can scaffold any containerizable project with one command.
- [ ] **SCAF-02**: Scaffolding generates or validates its Dockerfile and GitHub Actions workflow.
- [ ] **SCAF-03**: Scaffolding creates the application's GitOps configuration from one canonical slug.
- [ ] **SCAF-04**: Generated workloads include health probes and private GHCR pull credentials.
- [ ] **SCAF-05**: Scaffolding reports created resources, deployment status, and the expected URL.
- [ ] **SCAF-06**: T3 applications work out of the box while non-T3 containers can provide their own image configuration.

### Public Exposure

- [ ] **PUBLIC-01**: Applications remain LAN-only unless explicitly marked public.
- [ ] **PUBLIC-02**: Public opt-in creates the required Cloudflare DNS record.
- [ ] **PUBLIC-03**: Public traffic traverses the AWS Mikrotik path to NPM and the k3s ingress.
- [ ] **PUBLIC-04**: Public exposure defaults to deny and does not expose administrative interfaces.

### End-to-End Validation

- [ ] **E2E-01**: One real application deploys from git push to a valid-TLS hostname without manual wiring.
- [ ] **E2E-02**: The validation application connects to Postgres and authenticates through Zitadel.
- [ ] **E2E-03**: A failed deployment is visible and recoverable through git revert.
- [ ] **E2E-04**: The platform recovers after an MS-01 restart with correct VM/LXC startup ordering.
- [ ] **E2E-05**: A runbook documents bootstrap, deployment, troubleshooting, backup, and recovery.

## Future Requirements

### Platform Experience

- **DX-01**: Platform automatically provisions a dedicated Postgres database and role per application.
- **DX-02**: Operator receives deployment success and failure notifications.
- **DX-03**: Applications appear automatically in a homelab service dashboard.
- **DX-04**: Operator can decommission an application and its associated resources with one command.
- **DX-05**: Platform automatically provisions Zitadel OIDC clients for scaffolded applications.

### Operations

- **OPS-01**: Renovate proposes platform and application dependency updates.
- **OPS-02**: Applications can opt into staging environments and controlled promotion.
- **OPS-03**: Platform provides centralized metrics, logs, and alerting.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-node or HA k3s | One physical host provides no real hardware redundancy |
| Stateful services inside k3s | The cluster must remain disposable without risking persistent data |
| Docker-in-LXC | Avoid Proxmox nesting and AppArmor fragility |
| Self-hosted container registry | GHCR removes infrastructure and maintenance overhead |
| Service mesh | No v1 requirement justifies its operational complexity |
| Preview environments | Solo development does not justify per-PR lifecycle overhead |
| Imperative deployment CLI | Git remains the sole deployment source of truth |
| Full observability stack | Deferred until the deployment platform itself is validated |

## Traceability

Roadmap phase mappings will be populated during roadmap approval.

**Coverage:**
- v1.0 requirements: 37 total
- Mapped to phases: 0
- Unmapped: 37

---
*Requirements defined: 2026-07-07*
*Last updated: 2026-07-07 after v1.0 scope approval*
