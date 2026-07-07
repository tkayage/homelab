# Infrastructure prerequisites

This document records the non-secret evidence and approvals behind [`infrastructure/inventory.json`](../infrastructure/inventory.json). The inventory is canonical for mutable identifiers, addresses, sizes, dependencies, and startup settings. Never commit tokens, passwords, cookies, private keys, authenticated response bodies, or recovery codes.

## Approved guest topology

Exactly three new guests are approved. Phase 1 records their contract and does not provision them.

| Guest | Kind | VMID | IPv4 | DNS | vCPU | Memory | Disk | Startup |
|---|---|---:|---|---|---:|---:|---:|---|
| `postgres-01` | LXC | 120 | `10.10.30.100` | `postgres.app.kayage.co` | 2 | 4096 MiB | 64 GiB | order 10, delay 30s |
| `services-01` | VM | 121 | `10.10.30.101` | `services.app.kayage.co` | 4 | 8192 MiB | 64 GiB | order 20, delay 30s |
| `k3s-01` | VM | 122 | `10.10.30.102` | `k3s.app.kayage.co` | 4 | 8192 MiB | 64 GiB | order 40, delay 30s |

`postgres-01` runs native PostgreSQL. `services-01` runs one Docker Compose project containing Valkey, NATS with JetStream, and Debezium. Compose owns internal dependency order and health checks. Valkey and JetStream data are durable; Debezium runtime state is ephemeral and depends on reachable PostgreSQL and healthy NATS. These services are not Proxmox guests, and Docker-in-LXC is prohibited.

`k3s-01` depends on the guest-level identities `postgres-01`, `services-01`, and `zitadel-existing`. It must not model Compose service names as Proxmox boot dependencies.

## Capacity evidence and approvals

The operator approved the guest sizes above, a maximum vCPU/thread ratio of 2.5, and minimum RAM and storage headroom of 20% on 2026-07-07.

| Check | Measured inputs | Result |
|---|---|---|
| CPU | 32 existing vCPU + 10 planned vCPU; 20 physical threads | 2.1 ratio; passes maximum 2.5 |
| Memory | 52736 MiB existing + 20480 MiB planned; 96290.6 MiB host memory | approximately 23.9% remains; passes minimum 20% |
| Storage (`local-lvm`) | 323.15 GiB existing + 192 GiB planned | approximately 69.9% remains; passes minimum 20% |

Capacity evidence came from a read-only Proxmox guest, node, and storage inventory recheck. Resource totals for the three planned guests are 10 vCPU, 20480 MiB memory, and 192 GiB disk.

## Site and network evidence

| Canonical inventory path | Outcome | Evidence |
|---|---|---|
| `site.proxmox.version` | `PVE 8.4.19`, verified | PVEAuditor API metadata |
| `site.proxmox.node` | `proxmox`, verified | Proxmox node listing |
| `site.proxmox.physical_cores` | 14, verified | Node CPU topology |
| `site.proxmox.physical_threads` | 20, verified | Node CPU topology |
| `site.network.bridge` | `vmbr0`, verified | Proxmox network observation |
| `site.network.vlan` | `untagged`, verified | Read-only Proxmox network observation found no VLAN tag and no VLAN-aware setting on active `vmbr0` |
| `site.network.subnet` | `10.10.30.0/24`, verified | Proxmox and RouterOS observation |
| `site.network.gateway` | `10.10.30.1`, verified | RouterOS observation |
| `site.network.dns_suffix` | `app.kayage.co`, verified | Operator approval |
| `site.network.dhcp_exclusion_static_range` | `10.10.30.100-10.10.30.200`, verified for selected `.100-.102` addresses | RouterOS state and collision probes |
| `site.network.npm_identity` | `proxy.kayage.co` / `10.10.30.237` / LXC 111, verified | Operator-confirmed local identity and authenticated NPM API check |

The Cloudflare API had no public records for `proxy.kayage.co` or `zitadel.kayage.co`. That is consistent with these being operator-confirmed local-only DNS identities and is not evidence of public DNS publication.

## Existing systems

Existing Zitadel, NPM, Cloudflared, and Frigate remain separate LXCs under `manual-existing` ownership. Phase 1 does not re-provision, resize, restart, or reconfigure them.

Zitadel is LXC 112 at `10.10.30.236`, with local DNS identity `zitadel.kayage.co`, 1 vCPU, 1024 MiB RAM, and 8 GiB disk. Its observed configuration remains authoritative for current state. The operator approved desired startup metadata of order 15 and delay 30 seconds for later owner-controlled mutation; this approval does not claim that Phase 1 applied it or authorize a resize.

NPM is LXC 111 at `10.10.30.237`, with local DNS identity `proxy.kayage.co`. The operator approved desired startup metadata of order 30 and delay 30 seconds for later owner-controlled mutation. PostgreSQL, `services-01`, and k3s use orders 10, 20, and 40 respectively, all with 30-second delays.

## External namespaces and access

| Fact/system | Verified non-secret outcome | Secret-store label |
|---|---|---|
| Cloudflare | `kayage.co` and `hapa.dev` active | `homelab/cloudflare/platform-zone` |
| GitHub | private `tkayage/gitops-homelab`, default branch `main`, readable | `homelab/github/gitops-automation` |
| GHCR | owner `tkayage`; package-read check succeeded | `homelab/ghcr/cluster-pull` |
| Proxmox | PVEAuditor authentication and inventory reads succeeded | `homelab/proxmox/opentofu` |
| Mikrotik | authenticated RouterOS REST reads succeeded | `homelab/mikrotik/lan-automation` |
| NPM | authenticated API enumerated proxy hosts | `homelab/npm/platform-automation` |

These checks prove the read paths used to gather evidence. Later mutation phases must use identities scoped to only their declared resources and must verify write/deny boundaries before changing external systems.

## Completion gate

The three-guest topology, capacity policies, verified untagged LAN attachment, Plan 01-06 topology validator, and Plan 01-07 final gate have passed their recorded checks. Storage-headroom derivation remains pending until Plan 01-08 records measured usable pool capacity and validates the resulting arithmetic; Phase 1 must then be re-verified. All Phase 1 activity remains observational and documentation-only: no guest, network, or existing service was provisioned or mutated.
