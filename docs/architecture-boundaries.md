# Architecture and ownership boundaries

## Approved topology

The platform runs on the single Proxmox host identified by `site.proxmox.node` in [`infrastructure/inventory.json`](../infrastructure/inventory.json). Exactly three new guests are approved: `postgres-01`, a native PostgreSQL LXC; `services-01`, a VM running Valkey, NATS with JetStream, and Debezium in one Docker Compose project; and `k3s-01`, a disposable single-node k3s VM. Docker-in-LXC is prohibited. Existing Zitadel, NPM, Cloudflared, and Frigate remain separate existing LXCs. Durable application data remains outside k3s.

Local clients resolve application names through Mikrotik and enter through Nginx Proxy Manager before the k3s ingress. Public exposure is a separate, explicit opt-in path. Mutable names, addresses, resource allocations, guest identifiers, and startup settings are read from the inventory; they are deliberately not duplicated here.

Phase 1 only defines and validates this contract. It does not provision, resize, restart, reconfigure, or otherwise mutate infrastructure or external services.

## Responsibility contract

The table schema is: canonical inventory ID/path, lifecycle owner, configuration owner, state class, trust boundary.

The lifecycle and configuration columns use only the canonical owner enums `argocd`, `opentofu`, `config-automation`, and `manual-existing`. Each row assigns exactly one owner for each concern. An owner may consume another owner's output but must not manage resources across that boundary.

| System/capability ID | Canonical inventory ID/path | Lifecycle owner | Configuration owner | State class | Trust boundary |
|---|---|---|---|---|---|
| k3s-01 | `guests[id=k3s-01]` | opentofu | config-automation | ephemeral-disposable | Proxmox guest boundary; host lifecycle is external to Kubernetes, while in-guest bootstrap ends before Argo CD desired state begins |
| postgres-01 | `guests[id=postgres-01]` | opentofu | config-automation | durable | Dedicated LXC boundary; database files and recovery material never become k3s lifecycle state |
| services-01 | `guests[id=services-01]` | opentofu | config-automation | mixed | Dedicated VM boundary; Docker Compose owns internal ordering and health checks for Valkey, NATS/JetStream, and Debezium |
| valkey | `guests[id=services-01].services[id=valkey]` | config-automation | config-automation | durable | Compose service boundary inside `services-01`; not a Proxmox guest |
| nats | `guests[id=services-01].services[id=nats]` | config-automation | config-automation | durable | Compose service boundary inside `services-01`; bounded JetStream storage remains outside Kubernetes |
| debezium | `guests[id=services-01].services[id=debezium]` | config-automation | config-automation | ephemeral | Compose service boundary inside `services-01`; depends on PostgreSQL and healthy NATS without owning their durable data |
| zitadel-existing | `guests[id=zitadel-existing]` | manual-existing | manual-existing | durable | Pre-existing identity-system boundary; Phase 1 and platform automation are observe-only |
| kubernetes-desired-state | `responsibilities[capability=kubernetes-resources]` | argocd | argocd | declarative-rebuildable | Inside-k3s API boundary only; excludes VM/LXC, router, DNS provider, proxy, and native-service lifecycle |
| vm-lxc-lifecycle | `responsibilities[capability=guest-and-external-infrastructure-lifecycle]` | opentofu | opentofu | declarative-infrastructure | Proxmox API boundary; excludes operating-system/service configuration and Kubernetes objects |
| native-service-configuration | `responsibilities[capability=native-service-configuration]` | config-automation | config-automation | declarative-rebuildable | Guest operating-system boundary; excludes guest creation and application data ownership |
| local-exposure | `site.network` | opentofu | config-automation | declarative-edge | Mikrotik/NPM boundary; local routing automation must not grant public reachability or expose administrative interfaces |
| public-opt-in | `responsibilities[capability=guest-and-external-infrastructure-lifecycle]` | opentofu | config-automation | explicit-opt-in-edge | Public DNS and edge boundary; default deny, application-scoped approval, and no implicit promotion from local exposure |

`local-exposure` and `public-opt-in` reference current canonical inventory anchors because the Phase 1 schema has no separate capability records for them. Later schema changes may introduce narrower paths, but must preserve the ownership split and migrate consumers atomically.

## Lifecycle and durability rules

- `opentofu` owns creation and destruction of declared Proxmox guests and approved external infrastructure. It does not configure native software or submit Kubernetes resources.
- `config-automation` owns operating-system and native-service configuration after a guest exists. It does not create guests or manage Kubernetes desired state.
- `argocd` exclusively owns Kubernetes desired state. Bootstrap automation may install Argo CD, but steady-state Kubernetes resources must not be co-managed by another owner.
- `manual-existing` retains both lifecycle and configuration authority for Zitadel unless a later reviewed contract explicitly transfers ownership.
- Durable state must survive disposal of `k3s-01`. Rebuilding that VM must not delete database, message-stream, identity, backup, or secret-recovery state.
- A resource is changed through its assigned owner. Emergency manual intervention must be reconciled back to that owner's source of truth before normal automation resumes.

## Startup sequencing and readiness

Proxmox startup order and delay fields under each `guests[]` entry control deterministic guest boot sequencing after the physical host starts: PostgreSQL order 10, existing Zitadel order 15, `services-01` order 20, existing NPM order 30, and k3s order 40, each with a 30-second delay. Existing-system values are approved desired metadata for later owner-controlled mutation; Phase 1 does not apply them. These settings establish guest dependency order only; a delay is not evidence that a service is ready.

Inside `services-01`, Docker Compose—not Proxmox—controls Valkey, NATS/JetStream, and Debezium dependency order and protocol-specific health checks. Compose-internal readiness must never be modeled as separate Proxmox startup orders.

Later configuration and end-to-end phases must perform protocol-specific readiness checks before dependents are considered available. In particular, Debezium readiness depends on reachable Postgres and NATS services, and application readiness depends on the required shared services and Zitadel. A successful guest boot alone must never satisfy those checks.

## Security boundaries

- Operator-to-dashboard/API access uses the least-privilege identities described in `credentials[]`; secret values remain in an operator-controlled store and are injected only at execution time.
- External edge automation may manage only declared platform records. It cannot expose Proxmox, Mikrotik, NPM administration, Argo CD administration, or native-service administration.
- Git contains desired state and encrypted secret artifacts where later phases explicitly permit them, never plaintext credentials or credential-bearing command output.
- Inventory identifiers and paths are the shared contract between owners. Copying mutable IPs, names, sizes, or guest settings into automation creates a competing source of truth and is prohibited.
- Public reachability requires an explicit per-application opt-in. LAN availability does not imply public authorization.

## Phase 1 mutation prohibition

All Phase 1 checks are read-only observations, offline validation, and operator approvals. Provisioning and mutation begin only in their later roadmap phases after the prerequisite and capacity gates pass.
