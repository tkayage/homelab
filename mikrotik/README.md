# Homelab Network — MikroTik Architecture

This documents the current network design across both MikroTik devices, why each
architectural decision was made, and where to find config backups. Last verified
against live device state: **2026-08-12**.

## Devices

| Device | Model | Management IP | Role |
|---|---|---|---|
| `hap-ax3` | MikroTik hAP ax³ (C53UiG+5HPaxD2HPaxD) | `10.10.10.1` | Core router — dual-WAN, WiFi, firewall, self-hosted apps |
| `crs310` | MikroTik CRS310-8G+2S+IN | `10.10.10.2` | Distribution switch — hardware L3 routing for CCTV/Servers/NAS |

Both run RouterOS 7.23.3. SSH access: user `tonny`, key-based auth.

Config backups (RouterOS `/export`, sensitive values masked by default): [`backups/`](backups/).
Regenerate with `ssh tonny@<ip> "/export" > backups/<name>-<date>.rsc`.

> **Known issue to fix:** the `pihole` app's `FTLCONF_webserver_api_password` was
> found set to the literal value `password` during the last export. This has been
> redacted in the backup file — go set a real password on the router directly
> (`/app pihole` or the Pi-hole web UI) and update this note once done.

---

## Physical topology

```
Internet (YAS 5G)         Internet (DATAFLOW, microwave)
       │                          │
    ether4                     ether5
       └──────────┐    ┌──────────┘
                hAP ax³ (10.10.10.1)
                Apollo WiFi (2.4GHz)   Skynet WiFi (5GHz)
                       │
                    ether1 (2.5G trunk, all VLANs tagged)
                       │
                  CRS310 (10.10.10.2)
          ┌──────┬──────┬──────┬──────┬────────┐
       ether2  ether3  ether4  ether5  ether6  ether7/8, SFP+1/2
        NAS    MS-01    CCTV     TV   NAS 2.5G   free
      (1GbE) (Proxmox) (cams)  (100M) (adapter)
```

`ether3` (MS-01) is the Proxmox host running the bulk of the self-hosted stack
(mariadb, zitadel, nginxproxymanager, frigate, homeassistant, ollama, etc. — see
[Servers VLAN inventory](#servers-vlan-device-inventory) below). `ether4` (CCTV)
feeds an unmanaged switch fanning out to the cameras. The NAS (Synology DS423+)
has two active links: its onboard 1GbE port and a USB 2.5GbE adapter.

---

## VLAN & addressing scheme

| VLAN ID | Name | Subnet | Gateway lives on | Notes |
|---|---|---|---|---|
| 1 (native) | bridge | `10.10.0.0/24` | ax³ | Untagged/default network |
| 10 | Management | `10.10.10.0/24` | ax³ | Router/switch admin access |
| 20 | CCTV | `10.10.20.0/24` | **CRS310** | Cameras — no internet access (firewalled) |
| 30 | Servers | `10.10.30.0/24` | **CRS310** | Proxmox stack, see inventory below |
| 40 | NAS | `10.10.40.0/24` | **CRS310** | Synology DS423+ |
| 50 | lan | `10.10.50.0/24` | ax³ | Actually the **Skynet** WiFi network (legacy name) |
| 60 | Apollo Guests | `10.10.60.0/24` | ax³ | The **Apollo** WiFi network |

VLANs 20/30/40 have their gateway on the CRS310, not the ax³ — see
[Local L3 offload](#local-l3-offload-cctvserversnas) for why.

A VLAN 80 ("Camera Config", `192.168.1.0/24`) previously existed for one-time
camera setup and was fully removed — it collided with the DATAFLOW WAN subnet.

---

## Dual-WAN design

Two independent ISPs terminate on the ax³:

- **YAS** (`ether4`) — mobile/5G link, gateway `192.168.188.1`
- **DATAFLOW** (`ether5`) — microwave link, gateway `192.168.1.1`

Both are live simultaneously, split by traffic type rather than pure failover,
using policy routing (`mangle` + custom routing tables):

| Traffic | Primary WAN | Failover |
|---|---|---|
| Apollo WiFi (2.4GHz) | YAS (`to-yas` table) | DATAFLOW |
| Skynet WiFi + all wired VLANs | DATAFLOW (`to-dataflow` table) | YAS |
| Site-to-site tunnel to AWS (`wg-aws`) | DATAFLOW (`wg-aws-route` table) | YAS |
| Router's own traffic / unmarked | YAS (`main` table) | DATAFLOW |

**Why split by device type instead of just load-balancing:** keeps WiFi and wired
traffic from competing for the same uplink, and gives predictable behavior — you
always know which ISP a given device is using. Each table carries two default
routes (distance 1 primary, distance 2 backup) with `check-gateway=ping`, so a
dead uplink is detected and traffic automatically shifts to the other ISP without
manual intervention.

**Why internal traffic is explicitly excluded:** the split only applies to
internet-bound traffic. Two `mangle` bypass rules run first and `accept`
(skip marking) anything destined for: private/internal address ranges
(`skynet-local` list — covers all RFC1918 space, so this also naturally covers
the AWS VPC range and the back-to-home-vpn subnet), or the Selcom payment
API/PayPoint endpoints (`selcom-paypoint` list, since that traffic has its own
dedicated route through the `wg-aws` tunnel in the `main` table). Without this
exclusion, marked traffic would only ever consult its assigned table — which
holds nothing but a default route — and local/VPN traffic would get sent out to
an ISP gateway instead of delivered correctly.

**Skynet's routing history:** Skynet WiFi originally had a mangle rule forcing
its traffic through the `wg-aws` WireGuard tunnel to AWS (an always-on-VPN
design). That rule was retired — Skynet now uses the same plain DATAFLOW path as
other wired traffic — per explicit decision when the WAN split was built.

---

## Local L3 offload (CCTV/Servers/NAS)

VLANs 20 (CCTV), 30 (Servers), and 40 (NAS) route through the **CRS310's own
hardware** (Marvell 98DX226S switch chip, `l3-hw-offloading=yes`) instead of the
ax³. This was a deliberate migration, not the original design.

**Why:** these three networks talk to each other constantly (cameras → Frigate
NVR → NAS backups) and physically terminate on the same switch. Before this
change, that traffic had to travel up the trunk to the ax³ for routing and back
down again — a real, measured cost: roughly **36% of all trunk traffic was pure
hairpin waste** from this pattern alone. Local routing eliminates that round
trip entirely; verified post-migration latency between these VLANs is
sub-millisecond (270-600μs).

**What stayed on the ax³:** VLAN 50 (Skynet) was deliberately *not* migrated —
its WiFi radio lives on the ax³ itself, so wireless clients always hit the ax³
first regardless of where the VLAN 50 gateway lives; moving it would add
complexity with no hop-count benefit.

**DHCP for these three networks also now runs on the CRS310**, not the ax³ —
necessary since DHCP needs to run wherever the gateway IP lives. Every
previously-known device was given a **static reservation** (not left dynamic)
before cutover, specifically because several of these are production services
(database, identity provider, backup server) referenced by IP elsewhere — an
uncontrolled IP change on lease renewal would have broken things silently. See
the full device list below.

**Security implication handled during migration:** the firewall rule blocking
CCTV from reaching the internet originally matched `in-interface=CCTV`. After
migration, camera-sourced internet-bound traffic arrives at the ax³ via a
different path (through the CRS310's own uplink), so an interface-based rule
would silently stop matching. It was rewritten to match `src-address=10.10.20.0/24`
with `out-interface-list=WAN` instead — topology-independent, and now blocks
both YAS *and* DATAFLOW (an interface-only rule only ever covered YAS, meaning
cameras had a live gap to reach the internet via DATAFLOW from the moment the
WAN split went in, until this fix).

### Servers VLAN device inventory

All of the following are on `10.10.30.0/24`, mostly running as VMs/containers on
the `MS-01` Proxmox host, each pinned to a static DHCP reservation on the CRS310:

| IP | Host | Service |
|---|---|---|
| `.228` | proxmox-backup-server | Backup target |
| `.230` | termix | — |
| `.232` | hackintoshsiPro | — |
| `.234` | proxmox | Hypervisor |
| `.235` | frigate | NVR — camera stream target |
| `.236` | zitadel | Identity provider |
| `.237` | nginxproxymanager | Reverse proxy |
| `.238` | ollama | Local LLM |
| `.240` | sure | — |
| `.244` | cloudflared | Cloudflare Tunnel |
| `.248` | homeassistant | Home automation |
| `.250` | erp | — |
| `.251` | mariadb | Database |
| `.252` | erp-apps | — |

CCTV (`10.10.20.0/24`): 3 cameras (`.2`, `.3`, `.4`), also statically reserved.

NAS (`10.10.40.0/24`): Synology DS423+, dual-homed —
- `10.10.40.2` — USB 2.5GbE adapter (primary; this is the well-known/referenced address)
- `10.10.40.3` — onboard 1GbE port (fallback path)

Both interfaces are unbonded (separate IPs, not LACP) — deliberate, since the
dominant traffic pattern is single-flow (backups, NAS↔Proxmox), and LACP doesn't
split a single flow across links anyway. The 2.5GbE path was deliberately given
the "known" `.2` address (rather than updating every reference elsewhere) by
swapping the static lease's MAC binding — everything that already pointed at
`.2` silently started using the faster link with zero other changes needed.

---

## Remote access & site-to-site VPN

Two separate WireGuard tunnels exist, serving different purposes:

**`back-to-home-vpn`** — road-warrior remote access (e.g., for managing the
network while away). The router is double-NAT'd behind both ISPs' own CPEs
(neither hands out a public IP), so this uses **MikroTik's Cloud relay
service** rather than direct port-forwarding — the router makes an outbound
connection to a MikroTik relay server, and clients do the same, with the relay
bridging them. This sidesteps the NAT problem without needing port-forwards
configured on either ISP's equipment.

**`wg-aws`** — site-to-site tunnel to a MikroTik CHR router on AWS. This is
described as containing "the clients" — i.e., this is the actual production
VPN endpoint, not `back-to-home-vpn`. Used for the Selcom payment API/PayPoint
integration and AWS VPC access. Routed via the `wg-aws-route` table (DATAFLOW
primary, YAS failover — see [Dual-WAN design](#dual-wan-design)).

---

## Performance work

**Bridge hardware fast-path** — enabled on both devices
(`use-ip-firewall=no`, `allow-fast-path=yes`). By default, RouterOS forces all
bridged traffic through the software firewall/netfilter path if
`use-ip-firewall=yes` is set; neither device's firewall rules actually need to
inspect same-VLAN traffic, so this was pure unnecessary CPU cost. Confirmed
working via `bridge-fast-path-packets` counters actively climbing on both
devices post-change. Note: this only accelerates **same-VLAN** traffic — traffic
crossing VLANs (like CCTV→NVR before the L3 offload migration) was never
eligible for this shortcut regardless.

**Apollo WiFi band** — was locked to legacy `2ghz-g` (802.11g, ~54Mbps
theoretical ceiling for the whole SSID, confirmed via live client data showing
all connected devices capped at that band regardless of signal strength).
Changed to `2ghz-n` for broad compatibility with the mixed/guest devices that
use this SSID (chosen over `2ghz-ax` specifically for that reason). Skynet
(5GHz, `ax`) was never affected.

---

## Firewall & security notes

- CCTV cannot reach the internet (see [migration security fix](#local-l3-offload-cctvserversnas) above) — verified via live packet-drop counter on the rule.
- `back-to-home-vpn` peers restricted from reaching the LAN via a dedicated `forward` drop rule + address list.
- Internal/VPN traffic and Selcom API traffic are explicitly excluded from the WAN-split policy routing (see [Dual-WAN design](#dual-wan-design)).
- `/user group minimal` exists with a restricted policy (no write/password/sensitive/api access) — check who this is assigned to if auditing access.

---

## Known minor items (not urgent)

- CRS310 `ether2` (NAS 1GbE) and `ether5` (TV) show small TX packet drops
  (~3.7MB and ~600KB respectively over ~9 hours) — the two slowest ports on the
  switch, no flow control enabled anywhere, so brief bursts show as drops rather
  than backpressure. Not currently impactful; worth revisiting only if it grows.
- No QoS/queueing configured on the ax³ — fine at current usage, but no
  bufferbloat protection under heavy simultaneous load.
- `ether2`/`ether3` on the ax³ itself are unused (no-link).
