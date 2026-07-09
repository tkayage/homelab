# Requirements: Homelab Deploy Platform

**Defined:** 2026-07-07
**Milestone:** v1.0 End-to-End Homelab Deployment
**Core Value:** Push to git → app is live at `myapp.yourdomain.com` with valid TLS, no manual wiring.

## v1.0 Requirements

### Foundation

- [x] **INFRA-01**: Operator can reproducibly provision a single-node k3s VM on Proxmox.
- [x] **INFRA-02**: k3s starts automatically and remains disposable without risking persistent data.
- [x] **INFRA-03**: Infrastructure configuration defines explicit network, CPU, memory, and storage allocations.
- [x] **INFRA-04**: Operator can rebuild the k3s VM from documented automation.

### GitOps and Images

- [x] **GITOPS-01**: Argo CD reconciles the platform repository automatically.
- [x] **GITOPS-02**: Adding an app directory automatically registers and deploys the application.
- [x] **GITOPS-03**: Application repositories build and publish versioned images to GHCR on push.
- [x] **GITOPS-04**: CI updates the GitOps image reference and triggers deployment without manual cluster commands.
- [x] **GITOPS-05**: Secrets remain encrypted in git and recoverable after cluster replacement.
- [x] **GITOPS-06**: Operator can inspect deployment health and roll back through git revert.

### Local Exposure

- [x] **EDGE-01**: Local clients resolve application hostnames to NPM through Mikrotik DNS.
- [x] **EDGE-02**: NPM terminates valid TLS using a Cloudflare DNS-01 wildcard certificate.
- [x] **EDGE-03**: NPM and Traefik route each hostname to the correct application.
- [x] **EDGE-04**: Exposure supports websockets, large requests, and correct forwarded headers.
- [x] **EDGE-05**: Adding or removing an application requires no manual DNS, proxy, or certificate wiring.

### Shared Services

- [x] **SERV-01**: Postgres runs as a native service in a dedicated Proxmox LXC.
- [x] **SERV-02**: Valkey or Redis runs in the dedicated shared-services Compose VM with explicit memory limits.
- [x] **SERV-03**: NATS with JetStream runs in the dedicated shared-services Compose VM with bounded persistent storage.
- [x] **SERV-04**: Debezium runs in the dedicated shared-services Compose VM with controlled replication-slot WAL growth.
- [x] **SERV-05**: k3s applications reach shared services through stable LAN names.
- [x] **SERV-06**: Applications integrate with the existing Zitadel deployment without replacing it.
- [x] **SERV-07**: Postgres has a verified off-host backup and restore procedure.

> 2026-07-09 (05-07 hardening closure): SERV-07 live-verified with the hardened canonical procedure. Workstation 10.10.30.70 wrote `/mnt/pg-backup/postgres/pg_dumpall_20260709_081019.sql.gz`; restore-test copied that exact NAS artifact to a private local snapshot, reported SHA-256 `e6b85d04a11a7e3508770702604a996dd8eace9f9340abdf599d42f908a30e15`, restored it into a disposable postgres:17 container on services-01 with SQL error-stop semantics, and asserted restored Debezium role plus database state. See 05-VERIFICATION.md.

### Scaffolding

- [x] **SCAF-01**: Operator can scaffold any containerizable project with one command.
- [x] **SCAF-02**: Scaffolding generates or validates its Dockerfile and GitHub Actions workflow.
- [x] **SCAF-03**: Scaffolding creates the application's GitOps configuration from one canonical slug.
- [x] **SCAF-04**: Generated workloads include health probes and private GHCR pull credentials.
- [x] **SCAF-05**: Scaffolding reports created resources, deployment status, and the expected URL.
- [x] **SCAF-06**: T3 applications work out of the box while non-T3 containers can provide their own image configuration.

> 2026-07-09 (06-09 gap closure): Phase 6 verified complete after hardening the scaffolder's production path. Non-dry-run publish now requires a GHCR pull token from `--pull-token-file` or `GHCR_PULL_TOKEN`, plaintext `pull-secret.yaml` is mode 0600 and removed on success/failure, and the generated GitHub Actions GitOps push retry loop exits nonzero after exhausted retries. Offline proof: `go test -C scaffold ./...` and `bash scripts/scaffold-verify.sh all`. Live push -> GHCR -> GitOps -> Argo validation remains the Phase 8 validation-app proof.

### Public Exposure

- [x] **PUBLIC-01**: Applications remain LAN-only unless explicitly marked public.
- [x] **PUBLIC-02**: Public opt-in creates the required Cloudflare DNS record.
- [x] **PUBLIC-03**: Public traffic traverses the AWS Mikrotik path to NPM and the k3s ingress.
- [x] **PUBLIC-04**: Public exposure defaults to deny and does not expose administrative interfaces.

> 2026-07-09 (Phase 7 public exposure): Public exposure is now default-deny with explicit `--public` manifest metadata. Public DNS is per-host only, not wildcard. `scripts/public-edge.sh` provides preflight/default-deny/status/enable/disable/reachability/admin-scan commands. Verified with `go test -C scaffold ./...`, `bash scripts/scaffold-verify.sh all`, `bash tests/test-public-edge.sh static`, `bash scripts/public-edge.sh preflight`, `bash scripts/public-edge.sh assert-default-deny edge-smoke`, and `bash scripts/public-edge.sh scan-admin`. Full public enable/reach/disable is deferred to Phase 8's real validation app.

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
| Docker-in-LXC | Docker Compose runs in a dedicated VM to avoid Proxmox nesting and AppArmor fragility |
| Self-hosted container registry | GHCR removes infrastructure and maintenance overhead |
| Service mesh | No v1 requirement justifies its operational complexity |
| Preview environments | Solo development does not justify per-PR lifecycle overhead |
| Imperative deployment CLI | Git remains the sole deployment source of truth |
| Full observability stack | Deferred until the deployment platform itself is validated |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 2 | Complete |
| INFRA-02 | Phase 2 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 2 | Complete |
| GITOPS-01 | Phase 3 | Complete |
| GITOPS-02 | Phase 3 | Complete |
| GITOPS-03 | Phase 6 | Complete |
| GITOPS-04 | Phase 6 | Complete |
| GITOPS-05 | Phase 3 | Complete |
| GITOPS-06 | Phase 3 | Complete |
| EDGE-01 | Phase 4 | Complete |
| EDGE-02 | Phase 4 | Complete |
| EDGE-03 | Phase 4 | Complete |
| EDGE-04 | Phase 4 | Complete |
| EDGE-05 | Phase 4 | Complete |
| SERV-01 | Phase 5 | Complete |
| SERV-02 | Phase 5 | Complete |
| SERV-03 | Phase 5 | Complete |
| SERV-04 | Phase 5 | Complete |
| SERV-05 | Phase 5 | Complete |
| SERV-06 | Phase 5 | Complete |
| SERV-07 | Phase 5 | Complete |
| SCAF-01 | Phase 6 | Complete |
| SCAF-02 | Phase 6 | Complete |
| SCAF-03 | Phase 6 | Complete |
| SCAF-04 | Phase 6 | Complete |
| SCAF-05 | Phase 6 | Complete |
| SCAF-06 | Phase 6 | Complete |
| PUBLIC-01 | Phase 7 | Complete |
| PUBLIC-02 | Phase 7 | Complete |
| PUBLIC-03 | Phase 7 | Complete |
| PUBLIC-04 | Phase 7 | Complete |
| E2E-01 | Phase 8 | Pending |
| E2E-02 | Phase 8 | Pending |
| E2E-03 | Phase 8 | Pending |
| E2E-04 | Phase 8 | Pending |
| E2E-05 | Phase 8 | Pending |

**Coverage:**

- v1.0 requirements: 37 total
- Mapped to phases: 37
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-07*
*Last updated: 2026-07-09 after Phase 7 public exposure*
