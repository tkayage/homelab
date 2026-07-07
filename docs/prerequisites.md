# Infrastructure prerequisites

This checklist resolves the blocked and proposed records in [`infrastructure/inventory.json`](../infrastructure/inventory.json). Record values only in the inventory; this document records procedures, outcomes, evidence references, and approvals. Never paste tokens, passwords, cookies, private keys, or authenticated command output into either file. Use environment-variable names or interactive authentication, and keep values in the named secret store.

## Site facts

For every observation, update the inventory object's `value`, set `status` to `verified`, retain a concise `validation`, replace `source` with the evidence reference, and record an RFC 3339 timestamp. The group rows below are navigation keys; leaf rows are the write targets.

| Canonical inventory JSON path | Required observation | Non-secret verification procedure | Outcome | Evidence source | Timestamp |
|---|---|---|---|---|---|
| site.proxmox | Proxmox host facts | Complete every `site.proxmox.*` leaf below from the same observation window. | pending | pending | pending |
| site.proxmox.version | Installed PVE version | Interactively authenticate, then run `pveversion`; retain the version only. | pending | Proxmox CLI or UI | pending |
| site.proxmox.node | Target node identifier | Run `pvesh get /nodes --output-format json` and retain the intended node name. | pending | Proxmox API listing | pending |
| site.proxmox.physical_cores | Measured physical core count | Run `lscpu --json`; cross-check sockets, cores per socket, and online CPUs. | pending | Host `lscpu` observation | pending |
| site.proxmox.physical_threads | Measured physical thread count | Run `lscpu --json`; record online logical CPUs used by the approved CPU accounting basis. | pending | Host `lscpu` observation | pending |
| site.proxmox.usable_memory_mib | RAM usable for guests after host reserve | Compare `pvesh get /nodes/$PVE_NODE/status --output-format json` with the approved host reserve. `$PVE_NODE` is an environment variable. | pending | Proxmox node status | pending |
| site.proxmox.storage_pools | Storage identifiers and usable GiB per target pool | Run `pvesm status --output-format json`; retain identifiers, type, active state, and usable capacity, not credentials. | pending | Proxmox storage status | pending |
| site.proxmox.existing_committed_vcpu | Existing configured vCPU commitment | List all existing guests with `pvesh`; total configured vCPUs, including the retained Zitadel guest. | pending | Proxmox guest inventory | pending |
| site.proxmox.existing_committed_memory_mib | Existing configured memory commitment | List all existing guests and total configured memory MiB, including Zitadel. | pending | Proxmox guest inventory | pending |
| site.proxmox.existing_committed_storage_gib | Existing configured disk commitment | List guest volumes and total provisioned GiB on target storage, including Zitadel. | pending | Proxmox guest and storage inventory | pending |
| site.proxmox.measurement_timestamp | Shared host measurement time | Record the RFC 3339 timestamp after the preceding observations are complete. | pending | Operator clock | pending |
| site.network | LAN facts | Complete every `site.network.*` leaf below from Mikrotik and Proxmox observations. | pending | pending | pending |
| site.network.bridge | PVE LAN bridge identifier | Compare `$PVE_NODE` network configuration with the bridge used by an existing LAN guest. | pending | Proxmox node network view | pending |
| site.network.vlan | VLAN ID, or explicit untagged decision | Compare bridge/VLAN configuration with the Mikrotik interface and VLAN tables. | pending | Proxmox and Mikrotik state | pending |
| site.network.subnet | Platform LAN subnet in CIDR notation | Interactively authenticate to RouterOS and inspect `/ip/address/print detail without-paging`. | pending | Mikrotik address state | pending |
| site.network.gateway | LAN gateway IPv4 | Confirm the router address for the selected subnet from the same RouterOS listing. | pending | Mikrotik address state | pending |
| site.network.dns_suffix | Application/service DNS suffix | Compare RouterOS static DNS records with the approved Cloudflare zone; record only the suffix. | pending | Mikrotik DNS and Cloudflare zone metadata | pending |
| site.network.dhcp_exclusion_static_range | Collision-free static range outside DHCP | Inspect `/ip/dhcp-server/network/print`, `/ip/pool/print`, `/ip/dhcp-server/lease/print`, `/ip/arp/print`, and `/ip/dns/static/print`; probe each candidate before reservation. | pending | Mikrotik DHCP, ARP, and DNS state | pending |
| site.network.npm_identity | Stable NPM DNS name and IPv4 | Resolve the candidate name with `dig +short "$NPM_DNS_NAME"`, compare RouterOS DNS/ARP state, and confirm the NPM login page interactively. | pending | Mikrotik state and NPM UI | pending |

### External namespace and package facts

These later-phase facts do not yet have dedicated inventory leaves. Record their evidence here until the inventory schema introduces canonical paths; do not invent JSON members in an execution phase.

| Fact | Required observation | Safe verification | Outcome | Evidence source | Timestamp |
|---|---|---|---|---|---|
| Cloudflare zone/domain | Exact managed zone and active status | With `CLOUDFLARE_API_TOKEN` injected at runtime, request only zone metadata and redact headers/output before retaining evidence. | pending | Cloudflare zone metadata | pending |
| GitHub repository | Platform/GitOps repository owner and name | Use interactive `gh auth login`, then `gh repo view "$GITHUB_REPOSITORY" --json nameWithOwner,viewerPermission`. | pending | GitHub repository metadata | pending |
| GHCR package ownership | Account or organization owning application packages | Use interactive GitHub authentication and inspect package settings; retain owner/name and visibility only. | pending | GitHub Packages settings | pending |

## Existing Zitadel observation

Locate the entry where `guests[].id` is `zitadel-existing`; the selector below is the canonical logical path and avoids relying on array order. This is observe-only: do not resize, renumber, restart, or reconfigure the guest.

| Canonical inventory JSON path | Required observation | Outcome | Evidence source | Measurement timestamp |
|---|---|---|---|---|
| guests.zitadel-existing.observed_guest_id | Existing Proxmox guest ID | pending | Proxmox guest list | pending |
| guests.zitadel-existing.resources.vcpu | Configured vCPU | pending | Read-only guest configuration | pending |
| guests.zitadel-existing.resources.memory_mib | Configured memory MiB | pending | Read-only guest configuration | pending |
| guests.zitadel-existing.resources.disk_gib | Configured disk GiB | pending | Read-only guest configuration and volume listing | pending |
| guests.zitadel-existing.network.ipv4 | Observed stable IPv4 | pending | Guest config plus Mikrotik ARP/DHCP state | pending |
| guests.zitadel-existing.network.dns | Resolvable LAN DNS name | pending | Mikrotik static DNS plus `dig` | pending |
| guests.zitadel-existing.startup.order | Current Proxmox startup order | pending | Read-only guest configuration | pending |
| guests.zitadel-existing.startup.delay_seconds | Current Proxmox startup delay | pending | Read-only guest configuration | pending |
| guests.zitadel-existing.measurement_source | Non-secret command or UI reference covering the observations | pending | Operator evidence reference | pending |
| guests.zitadel-existing.measurement_timestamp | RFC 3339 time of observation | pending | Operator clock | pending |

Use a read-only listing such as `pct config "$ZITADEL_GUEST_ID"` after setting `ZITADEL_GUEST_ID` from the observed guest list. Redact descriptions or mount options if they contain environment-sensitive data; never commit raw authenticated output.

## Access verification

Each system row corresponds to the same `system` entry under `credentials[]` in the inventory. The secret-store label names a record, not its contents. Mark success only after the minimum-scope identity passes the non-mutating verification and a broader operation is either denied or demonstrably absent from its role.

| system ID | minimum scope | secret-store label | consumers | rotation procedure | revocation procedure | verification procedure | outcome | evidence source | timestamp |
|---|---|---|---|---|---|---|---|---|---|
| proxmox | Required VM/LXC and target-storage lifecycle on the selected node only | `homelab/proxmox/opentofu` | opentofu | Issue replacement identity, update runtime injection, run a read-only plan | Disable old token/identity after replacement succeeds | Set `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_USERNAME`, and secret reference at runtime; list only the target node/resources and confirm unrelated scope is denied | pending | Redacted role and successful request metadata | pending |
| mikrotik-lan | Read DHCP/network state; manage platform static DNS entries only | `homelab/mikrotik/lan-automation` | opentofu, config-automation | Create replacement credential in the same restricted group and update runtime injection | Disable/remove prior user after read-only verification | Authenticate interactively or inject `MIKROTIK_USERNAME` and secret reference; list DNS/DHCP state and confirm unrelated write scope is denied | pending | RouterOS group definition and redacted audit record | pending |
| npm | Manage platform proxy hosts/certificates without host or admin-system exposure | `homelab/npm/platform-automation` | opentofu, config-automation | Rotate through the supported NPM account/API workflow and update runtime injection | Revoke superseded sessions or identity | Authenticate interactively using `NPM_BASE_URL` and secret reference; enumerate platform proxy resources without retaining session material | pending | NPM role/account view and request status | pending |
| cloudflare | Zone read plus DNS edit for exactly the managed zone | `homelab/cloudflare/platform-zone` | opentofu, certificate-automation | Create a replacement zone-scoped token, update consumers, verify zone access | Revoke former token after all consumers pass | Inject `CLOUDFLARE_API_TOKEN`; request the intended zone metadata and confirm other zones are unavailable | pending | Token permission summary and redacted request status | pending |
| github | Contents read/write on explicitly selected app and GitOps repositories only | `homelab/github/gitops-automation` | github-actions, gitops-update-workflow | Rotate GitHub App/PAT or reinstall the repository-scoped app, then test workflow access | Revoke prior grant/token after workflow verification | Authenticate interactively with `gh`; inspect `GITHUB_REPOSITORY` permission and confirm no unselected repository grant | pending | GitHub App installation/permission view | pending |
| ghcr | Package read for required private images only | `homelab/ghcr/cluster-pull` | k3s-image-pull | Issue replacement package-read identity, update encrypted pull material, perform test pull | Revoke former identity after pull succeeds | Inject `GHCR_USERNAME` and secret reference through a credential helper; test manifest access for `GHCR_IMAGE` without printing authorization headers | pending | Package permission view and pull status | pending |

## Operator approvals

Approvals are structured evidence, not implied by completing measurements. Record the approved value/status in the inventory and complete every field below in the same review. Guest sizes refer to each proposed `guests[].resources` object.

| Approval | Canonical inventory JSON path | Proposed value | Accounting basis / rationale | Approver | Date | Outcome |
|---|---|---|---|---|---|---|
| guest sizes | guests[].resources | Per-guest vCPU, memory MiB, and disk GiB proposals | All proposed allocations plus verified existing commitments fit the three approved reserves; Zitadel is observed, not proposed | pending | pending | pending |
| memory reserve | capacity.policy.minimum_memory_headroom_percent | 20% | `(usable memory - existing commitments - proposed allocations) / usable memory`; protects host and guests from memory pressure | pending | pending | pending |
| storage reserve | capacity.policy.minimum_storage_headroom_percent | 20% | `(usable target storage - existing commitments - proposed allocations) / usable target storage`; protects operations, snapshots, and growth | pending | pending | pending |
| CPU policy | capacity.policy.cpu | mode: `minimum_uncommitted_thread_percent`; numeric threshold: 20%; accounting basis: existing committed vCPU plus proposed vCPU versus measured physical threads | Provides a measurable scheduling-headroom gate on the single host; approval must explicitly accept the mode, threshold, accounting basis, and workload-contention rationale | pending | pending | pending |

Compatibility coverage labels used by the Phase 1 documentation check map as follows; they are not alternate inventory write paths:

| Checklist coverage key | Canonical inventory target |
|---|---|
| capacity.host.physical_threads | site.proxmox.physical_threads |
| capacity.commitments.existing_vcpu | site.proxmox.existing_committed_vcpu |
| capacity.policy.cpu | capacity.policy.cpu |

## Completion gate

Do not authorize provisioning until all site and Zitadel facts are verified, collision checks pass, all six access outcomes are successful at least privilege, approvals name an approver/date, and the inventory validator passes. Phase 1 verification is observational and must not mutate Proxmox, RouterOS, NPM, Cloudflare, GitHub, GHCR, or Zitadel.
