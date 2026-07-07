# Architecture Research

**Domain:** GitOps homelab deployment platform (k3s on Proxmox, automated DNS/proxy/TLS per app)
**Researched:** 2026-07-07
**Confidence:** MEDIUM overall (cross-referenced community + official docs; provider-tier for web findings is LOW — key uncertain claims are flagged individually)

## Standard Architecture

### System Overview

```
                    INTERNET (opt-in public path)
                          │
              ┌───────────▼───────────┐
              │  Cloudflare DNS       │  A record: myapp.domain.com → CHR public IP
              │  (public zone)        │  (created by external-dns, annotation-gated)
              └───────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │  AWS Mikrotik CHR     │  dst-nat 80/443 → tunnel
              │  (public IP)          │
              └───────────┬───────────┘
                          │  WireGuard site-to-site
                          │  (home side initiates, keepalive 25s)
   ┌──────────────────────▼──────────────────────────────────────────┐
   │  HOME LAN                                                        │
   │  ┌────────────────┐      ┌─────────────────────┐                 │
   │  │ Mikrotik router│      │ Nginx Proxy Manager │◄── LAN clients  │
   │  │ LAN DNS        │─────►│ TLS termination     │    (split DNS:  │
   │  │ *.domain.com   │      │ wildcard DNS-01 cert│     *.domain →  │
   │  │  → NPM IP      │      └──────────┬──────────┘     NPM IP)     │
   │  └────────────────┘                 │ HTTP(S), Host header       │
   │  ┌──────────────────────────────────▼──────────────────────────┐ │
   │  │  PROXMOX MS-01 (vmbr0 bridge)                               │ │
   │  │  ┌───────────────────────────────┐  ┌─────────────────────┐ │ │
   │  │  │  k3s VM (ephemeral, apps only)│  │ Shared-service LXCs │ │ │
   │  │  │  ┌─────────┐ ┌─────────────┐  │  │ ┌────────┐┌───────┐ │ │ │
   │  │  │  │ Traefik │→│ App pods    │──┼──┼►│Postgres││Valkey │ │ │ │
   │  │  │  │ ingress │ │ (from GHCR) │  │  │ └────────┘└───────┘ │ │ │
   │  │  │  └─────────┘ └─────────────┘  │  │ ┌────────┐┌───────┐ │ │ │
   │  │  │  ┌──────────────────────────┐ │  │ │ NATS/JS││Debez. │ │ │ │
   │  │  │  │ Platform controllers:    │ │  │ └────────┘└───────┘ │ │ │
   │  │  │  │ ArgoCD, external-dns x2, │ │  │ ┌────────┐          │ │ │
   │  │  │  │ cert-manager             │ │  │ │Zitadel │(existing)│ │ │ │
   │  │  │  └──────────────────────────┘ │  │ └────────┘          │ │ │
   │  │  └───────────────────────────────┘  └─────────────────────┘ │ │
   │  └─────────────────────────────────────────────────────────────┘ │
   └──────────────────────────────────────────────────────────────────┘

   GITOPS CONTROL PLANE (out-of-band):
   dev server ──push──► app repo (GitHub) ──Actions──► GHCR image
                              │ (updates image tag / manifests)
                              ▼
                      platform repo (GitHub) ◄──watch── ArgoCD (in k3s)
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Platform repo (GitOps monorepo) | Single source of truth: cluster addons, shared-service endpoint definitions, one directory per app | GitHub repo, Kustomize/Helm per directory |
| App repos (one per project) | Source code, Dockerfile, CI workflow that builds → GHCR and bumps the tag in the platform repo | GitHub + Actions, scaffolded by the CLI tool |
| ArgoCD (in k3s) | Watches platform repo, reconciles cluster state; ApplicationSet auto-discovers `apps/*` directories | ArgoCD + one ApplicationSet (git directory generator) |
| Traefik (k3s bundled) | In-cluster ingress: routes by Host header to app Services | k3s default; ServiceLB exposes 80/443 on the VM IP |
| Nginx Proxy Manager | LAN edge reverse proxy: TLS termination with wildcard cert, forwards to Traefik | Existing NPM instance; ideally ONE wildcard proxy host |
| Mikrotik LAN DNS | Split-horizon resolution: `*.domain.com` → NPM LAN IP | Static DNS regexp entry (wildcard) or per-app records via external-dns webhook |
| cert-manager or NPM's certbot | Obtains wildcard cert via Cloudflare DNS-01 | NPM built-in DNS-01 for the NPM cert; cert-manager only if TLS is also needed inside the cluster |
| external-dns (Cloudflare instance) | Opt-in public exposure: creates Cloudflare A record → CHR public IP when an Ingress carries the "public" annotation | external-dns with `--annotation-filter`, Cloudflare provider |
| external-dns (Mikrotik instance, optional) | Per-app LAN DNS records if wildcard DNS is not used | mirceanton/external-dns-provider-mikrotik webhook sidecar |
| AWS Mikrotik CHR | Public ingress: dst-nat 80/443 across WireGuard to NPM | RouterOS v7 native WireGuard + NAT rules |
| Shared-service LXCs | Stateful services outside the disposable cluster | Native binaries; static LAN IPs; per-LXC Proxmox snapshots |
| Scaffolding CLI | One-shot per project: generates Dockerfile/CI/manifests, commits app directory to platform repo | Script/CLI on dev server |

## Recommended Project Structure

Two repo classes: **one platform monorepo** + **one repo per app**. Do NOT put deploy manifests in app repos — keep the GitOps source of truth in one place so ArgoCD watches a single repo and scaffolding is "commit a folder."

```
homelab-platform/                  # THE GitOps monorepo (ArgoCD watches this)
├── bootstrap/                     # ArgoCD install + root ApplicationSet (applied once, manually)
│   ├── argocd/                    # ArgoCD Helm values / install manifests
│   └── root-appset.yaml           # git directory generator over apps/* and platform/*
├── platform/                      # Cluster addons, deployed like apps
│   ├── external-dns-cloudflare/   # public-exposure controller (annotation-filtered)
│   ├── external-dns-mikrotik/     # (optional) per-app LAN DNS controller
│   ├── cert-manager/              # (only if in-cluster TLS is chosen)
│   └── shared-services/           # Service + EndpointSlice per LXC (postgres, valkey, nats, zitadel)
├── apps/                          # One directory per deployed app — scaffold target
│   └── myapp/
│       ├── kustomization.yaml
│       ├── deployment.yaml        # image: ghcr.io/you/myapp:<tag>  ← CI bumps this
│       ├── service.yaml
│       └── ingress.yaml           # host: myapp.domain.com (+ optional public annotation)
├── infra/                         # Non-k8s IaC (optional, applied by hand or CI)
│   ├── proxmox/                   # VM/LXC provisioning notes or Terraform/Ansible
│   ├── mikrotik/                  # RouterOS config exports (LAN + CHR)
│   └── npm/                       # NPM config (Terraform provider) if per-app hosts needed
└── scaffold/                      # The scaffolding CLI + templates

myapp/                             # Per-app repo (one per project)
├── src/ ...                       # T3 app source
├── Dockerfile
└── .github/workflows/deploy.yaml  # build → push GHCR → bump tag in homelab-platform
```

### Structure Rationale

- **`bootstrap/`:** The only thing ever applied manually (`kubectl apply`). Everything else flows through ArgoCD — this solves the "who deploys the deployer" problem.
- **`apps/` + ApplicationSet git generator:** Scaffolding becomes *zero-registration*: committing `apps/myapp/` makes ArgoCD create the Application automatically. No editing a central list, no app-of-apps YAML to maintain per app. This is the modern replacement for hand-rolled app-of-apps and fits the "push → live" goal directly.
- **Manifests in platform repo, not app repos:** ArgoCD needs read access to exactly one repo; app repos stay deployment-agnostic; the CI tag-bump commit gives an audit trail of every deploy. The alternative (manifests in app repos, one Application each) works but makes scaffolding do ArgoCD registration and multiplies repo credentials.
- **`infra/` kept separate from `platform/`:** ArgoCD must never manage the things it runs on (Proxmox, routers, NPM). Boundary: if it's a Kubernetes resource, ArgoCD owns it; otherwise it's `infra/` (documented or Terraform-applied).

## Architectural Patterns

### Pattern 1: Wildcard-first exposure (collapse per-app automation)

**What:** Make the LAN path per-app-automation-free: one Mikrotik static DNS **regexp entry** (`.*\.domain\.com` → NPM IP), one NPM **wildcard proxy host** (`*.domain.com` → Traefik on the k3s VM, forward Host header), one **wildcard cert** (Cloudflare DNS-01, managed by NPM's built-in certbot). Per-app "DNS + proxy + TLS" then reduces to the Ingress resource ArgoCD already deploys — routing happens in Traefik.
**When to use:** Default LAN path for every app.
**Trade-offs:** Massively less automation to build and nothing to drift. Cost: every subdomain resolves on the LAN even if no app exists (404 from Traefik — harmless), and all apps share one edge config. **Flag (LOW confidence):** NPM's wildcard *proxy-host domain* support has a mixed history ([issue #749](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/749), [#591](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/591)); wildcard *certificates* are definitely supported. Spike this in ~15 minutes before committing; fallback is Pattern 2.

**Example (Mikrotik regexp DNS):**
```
/ip dns static add regexp=".*\\.domain\\.com" address=192.168.1.10 comment="wildcard to NPM"
```

### Pattern 2: Annotation-driven controllers for per-record automation

**What:** Where per-app records are genuinely needed, run reconciling **in-cluster controllers**, not CI steps: external-dns (Cloudflare provider, `--annotation-filter=domain.com/public=true`) creates the public A record → CHR IP; external-dns with the [mirceanton Mikrotik webhook provider](https://github.com/mirceanton/external-dns-provider-mikrotik) (active, v1.6.3 June 2026, RouterOS 7.16, REST API auth) creates LAN records if you skip the wildcard; NPM proxy hosts, if per-app, via the [NPM Terraform provider](https://registry.terraform.io/providers/Sander0542/nginxproxymanager/latest/docs) or a small script hitting NPM's REST API.
**When to use:** Always for the public opt-in path (records must be per-app); for LAN DNS/NPM only if the wildcard spike fails.
**Trade-offs:** Controllers reconcile continuously (GitOps-native — delete the Ingress, the DNS record goes away), vs CI steps which are imperative, drift, and need router/NPM credentials in GitHub. The cost is two small extra deployments in the cluster. There is **no** Kubernetes controller for NPM — that seam is script/Terraform territory, another reason to prefer the wildcard.

**Example (opt-in public exposure — the entire per-app act):**
```yaml
# apps/myapp/ingress.yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/target: "203.0.113.7"   # CHR public IP
    domain.com/public: "true"                                # matched by --annotation-filter
```

### Pattern 3: Service-without-selector for LAN shared services

**What:** For each LXC service, define in `platform/shared-services/` a Kubernetes `Service` (no selector) plus a manual `EndpointSlice` carrying the LXC's static LAN IP. Apps connect to `postgres.shared-services.svc.cluster.local:5432` — stable in-cluster names, real IPs behind them.
**When to use:** All shared services (Postgres, Valkey, NATS, Debezium Connect REST, Zitadel).
**Trade-offs:** One 15-line YAML per service, changes only if an LXC IP changes (give LXCs DHCP reservations/static IPs). **Do not use `ExternalName`:** it is a CNAME — it cannot hold an IP (IPv4-looking values are treated as DNS labels and fail per [Kubernetes docs](https://kubernetes.io/docs/concepts/services-networking/service/)) and it breaks TLS hostname matching. Alternative — pods resolving `postgres.lan` via CoreDNS→Mikrotik upstream — works but couples app config to LAN DNS naming; the Service indirection keeps app manifests portable.

**Example:**
```yaml
apiVersion: v1
kind: Service
metadata: { name: postgres, namespace: shared-services }
spec:
  ports: [{ port: 5432 }]
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: postgres-1
  namespace: shared-services
  labels: { kubernetes.io/service-name: postgres }
addressType: IPv4
endpoints: [{ addresses: ["192.168.1.20"] }]
ports: [{ port: 5432 }]
```

### Pattern 4: Disposable cluster, durable edges

**What:** The k3s VM holds zero state and zero credentials that can't be re-derived from git + a small bootstrap secret set (Cloudflare token, GHCR pull secret, router creds). Rebuild = new VM + `kubectl apply -f bootstrap/` + inject secrets; ArgoCD reconverges everything. State (LXCs), edge (NPM, routers), and source of truth (GitHub) all live outside the blast radius.
**When to use:** This is the invariant that makes the whole design safe on one physical node.
**Trade-offs:** Requires discipline: any manual `kubectl` change is a bug. Secret bootstrap needs a defined procedure (sealed-secrets/SOPS decision belongs to STACK research).

## Data Flow

### Request Flow — Local (default) path

```
LAN client
  → DNS query myapp.domain.com → Mikrotik LAN DNS (wildcard/static entry)
  → resolves to NPM LAN IP
  → HTTPS to NPM :443 — TLS terminated (wildcard *.domain.com cert, DNS-01)
  → NPM forwards HTTP + Host header + X-Forwarded-* to Traefik (k3s VM IP :80)
  → Traefik matches Ingress host myapp.domain.com
  → Service → Pod
  → Pod (server-side) → shared-services Service → EndpointSlice → LXC (Postgres/NATS/…)
```

TLS terminates **once, at NPM**. The NPM→Traefik hop is plaintext HTTP on the trusted LAN/host bridge — acceptable for v1 and avoids double cert management (cert-manager becomes optional, not required). If in-cluster TLS is wanted later, add a cert-manager wildcard cert as Traefik's default and have NPM forward HTTPS.

### Request Flow — Public (opt-in) path

```
Internet client
  → Cloudflare DNS (DNS-only/grey-cloud A record, created by external-dns) → CHR public IP
  → CHR dst-nat 80/443 → across WireGuard tunnel → NPM LAN IP
  → NPM (same wildcard cert, same proxy host) → Traefik → pod (same as local from here)
```

The two paths **converge at NPM** — everything downstream is identical, which is what keeps public exposure a one-annotation opt-in rather than a second deployment target.

### WireGuard tunnel (CHR ↔ home)

Standard, well-trodden Mikrotik pattern (RouterOS v7 native WireGuard on both ends):

- **Home side initiates** (it's behind NAT; CHR has the public IP) with `persistent-keepalive=25`.
- Terminate the tunnel on the **home Mikrotik** (not on NPM/a VM) — the router owns routing; give the tunnel a /30 transfer net (e.g. `10.255.0.1` CHR ↔ `10.255.0.2` home) and route the LAN subnet over it from the CHR side.
- CHR: `dst-nat` tcp/80,443 → NPM LAN IP; accept WG UDP port in `input`, tunnel traffic in `forward`, **before** drop rules; MTU 1420 (drop to 1380–1412 if the home uplink is PPPoE).
- Client-IP tradeoff: `masquerade` on the CHR is simplest but NPM sees the CHR tunnel IP as the source. To preserve real client IPs, skip src-nat and ensure return traffic routes back via the tunnel (works cleanly since the home Mikrotik is the LAN gateway and holds the tunnel). Decide during the public-path phase; masquerade is a fine v1 default.

### GitOps deploy flow

```
dev: scaffold once → app repo (Dockerfile, CI) + apps/myapp/ dir in platform repo
push to app repo
  → GitHub Actions: docker build → push ghcr.io/you/myapp:sha
  → Actions commits image-tag bump to homelab-platform/apps/myapp/
  → ArgoCD (polling/webhook) detects platform repo change
  → ApplicationSet already generated the Application for apps/myapp/
  → sync: Deployment rolls, pulls from GHCR (imagePullSecret)
  → Ingress reconciled → (public apps) external-dns upserts Cloudflare record
```

The CI-writes-back-to-git step (rather than ArgoCD Image Updater or `:latest` + restart) keeps the deployed tag visible in git history — the GitOps property the project explicitly wants.

### Key Data Flows

1. **App traffic (both paths):** client → DNS → NPM → Traefik → pod. NPM is the single edge; Traefik is the single router-by-hostname.
2. **App → state:** pod → Service/EndpointSlice → LXC over the Proxmox bridge. Pod egress is SNAT'd to the k3s VM IP, so LXC-side allow-rules only need one source IP.
3. **Deploy:** git push → GHCR + tag bump → ArgoCD pull-based sync. Nothing on the LAN accepts pushes from the internet; the cluster pulls.
4. **CDC/eventing:** Postgres LXC → Debezium LXC (logical replication) → NATS JetStream LXC → app pods subscribe via the `nats` shared-service Service. Entirely LXC-side except the final subscription.

## Network Segmentation

**Recommendation for v1: one flat LAN segment (single vmbr0 bridge, existing subnet), enforced by host-level firewalls — not VLANs.**

- The k3s VM and all LXCs sit on the same Proxmox bridge with static IPs / DHCP reservations. Pod traffic leaves the VM SNAT'd to the VM's IP.
- Enforcement point: Proxmox firewall (or in-LXC firewalls) on each service LXC — allow its port only from the k3s VM IP, NPM, and the dev machine. This gives 90% of the segmentation value for 5% of the effort.
- VLAN-splitting (services VLAN vs apps VLAN vs LAN) on one physical node adds Mikrotik inter-VLAN routing/firewall complexity without a real trust boundary gain for a solo operator — everything still shares one hypervisor. Defer; the flat design doesn't preclude it later since all addressing is in one place (`infra/`).
- The only *hard* boundary that matters in v1 is **internet vs LAN**, and that's already handled by the opt-in CHR path — no inbound ports at home, tunnel initiated outbound.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| v1 (a few apps, LAN users) | Everything above as-is; single Traefik, single NPM, wildcard-first |
| ~10–30 apps | Nothing structural changes — this is the design's sweet spot; watch k3s VM RAM (ArgoCD + controllers ≈ 1–1.5 GB overhead) and give the VM room to grow |
| Second physical node ever added | Revisit: k3s agent on node 2, kube-vip/MetalLB instead of ServiceLB, Postgres replication between LXCs — explicitly out of scope now, and nothing in this design blocks it |

### Scaling Priorities

1. **First bottleneck:** k3s VM memory (single VM hosts every app + platform controllers). Fix: raise VM allocation; MS-01 supports 64–96 GB.
2. **Second bottleneck:** Postgres LXC as the shared database for many apps. Fix: per-app databases within the one instance first; a second Postgres LXC only when a workload demands it.

## Anti-Patterns

### Anti-Pattern 1: CI pipeline as the DNS/proxy automation engine

**What people do:** GitHub Actions steps that call the Mikrotik/NPM/Cloudflare APIs to create records and proxy hosts on deploy.
**Why it's wrong:** Imperative and one-shot — records drift, deletes never happen, router credentials live in GitHub, and a re-run of an old pipeline resurrects stale config. It also breaks the "git state = live state" invariant everywhere except the cluster.
**Do this instead:** Wildcard-first (Pattern 1) so most records never need creating; reconciling in-cluster controllers (Pattern 2) for the rest. CI only builds images and commits manifests.

### Anti-Pattern 2: Per-app ArgoCD Application YAML (hand-rolled app-of-apps)

**What people do:** Scaffolding appends an `Application` manifest to a central list for every new app.
**Why it's wrong:** A registration step that can be forgotten, merge-conflicts on one file, and duplicated boilerplate — exactly the manual wiring the project exists to eliminate.
**Do this instead:** One ApplicationSet with a git directory generator over `apps/*`. Scaffold = create a directory.

### Anti-Pattern 3: Hardcoding LXC IPs (or LAN hostnames) in app manifests

**What people do:** `DATABASE_URL=postgres://192.168.1.20:5432/...` in each Deployment.
**Why it's wrong:** IP changes fan out across every app; manifests aren't portable to a rebuilt network; `ExternalName` as a "fix" silently fails for IPs.
**Do this instead:** Pattern 3 — Service-without-selector + EndpointSlice, one place per service.

### Anti-Pattern 4: Letting state or edge config creep into the cluster

**What people do:** "Just this once" — a Postgres pod for a small app, an NPM container in k3s, manual kubectl edits.
**Why it's wrong:** Destroys the disposable-cluster invariant that the whole single-node design depends on; a cluster rebuild now loses data or the edge.
**Do this instead:** State in LXCs, edge in NPM/routers, everything in the cluster reproducible from git + bootstrap secrets.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Cloudflare (DNS + certs) | API token used by NPM certbot (DNS-01) and external-dns (public records) | Scope token to the one zone; two consumers, consider two tokens |
| GHCR | `imagePullSecret` in app namespaces; GitHub Actions `GITHUB_TOKEN` pushes | Private images need a PAT-based pull secret replicated per namespace (or one shared namespace — decide in scaffold design) |
| Mikrotik LAN router | One-time wildcard static DNS entry; optionally external-dns webhook (REST API, needs `api,rest-api,read,write` service account) | Webhook provider tested against RouterOS 7.16 |
| Mikrotik CHR (AWS) | WireGuard peer + dst-nat rules; config is static after setup | No per-app changes ever — per-app public exposure is DNS-only |
| NPM | One-time wildcard proxy host (spike!); fallback per-app via REST API/Terraform | No k8s controller exists for NPM |
| Zitadel LXC | Apps use OIDC against it via `zitadel.shared-services.svc` or its existing LAN hostname | Integrated as-is; issuer URL must match its cert/hostname — prefer its existing public hostname for OIDC issuer consistency |
| Shared-service LXCs | Service + EndpointSlice per service (Pattern 3) | Static IPs mandatory |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| NPM ↔ Traefik | HTTP, Host header + X-Forwarded-* preserved | The one hop where misconfig silently breaks per-app routing; verify header forwarding early |
| ArgoCD ↔ platform repo | HTTPS pull (poll or GitHub webhook) | Pull-based; no inbound access to cluster needed |
| CI ↔ platform repo | Commit (tag bump) with a scoped deploy key/PAT | The only write-path from CI into GitOps |
| Pods ↔ LXCs | TCP via Service/EndpointSlice; SNAT to VM IP | LXC firewalls allow the VM IP only |
| external-dns ↔ Cloudflare/Mikrotik | Controller → API, reconciling | Credentials as cluster secrets (bootstrap set) |
| Home Mikrotik ↔ CHR | WireGuard UDP, home-initiated | Only internet-facing surface at home is *outbound* |

## Suggested Build Order

Dependencies drive this ordering; each step is independently verifiable.

1. **Foundation:** k3s VM on Proxmox (static IP), kubectl access from dev server. *Verify: Traefik answers on VM IP :80.*
2. **GitOps engine:** platform repo skeleton, ArgoCD via `bootstrap/`, root ApplicationSet over `apps/*`. Deploy a `whoami` test app purely by committing a directory. *Everything after this ships through git.*
3. **LAN exposure spine:** Mikrotik wildcard DNS entry → NPM wildcard cert (Cloudflare DNS-01) → NPM wildcard proxy host → Traefik (**spike wildcard proxy-host support first**; fallback = per-app NPM automation via API). *Verify: `https://whoami.domain.com` green-lock on the LAN.*
4. **Shared services:** LXCs in dependency order — Postgres → Valkey → NATS/JetStream → Debezium (needs Postgres + NATS); Zitadel integration is config-only. Add Service/EndpointSlice definitions in `platform/shared-services/`. *Verify: test pod reaches `postgres.shared-services.svc`.* (Parallelizable with 5.)
5. **CI + scaffolding:** GH Actions template (build → GHCR → tag-bump commit), GHCR pull secret, scaffold CLI generating app repo files + `apps/<name>/` directory. *Verify: push to a test app repo → live on LAN with zero manual steps.*
6. **Public opt-in path:** WireGuard CHR↔home, dst-nat, external-dns (Cloudflare, annotation-filtered), `--public` flag in scaffold. *Verify: annotated app reachable from mobile data; un-annotated app is not.* (Independent of 4/5; can slot earlier or later.)
7. **v1 gate:** first real T3 app end-to-end through scaffold → push → live, using Postgres + Zitadel.

Rationale: 2 before 3 so the exposure spine itself is (partly) GitOps-managed; 3 before 5 so scaffolded apps are immediately reachable; 4 anytime after 2 but before 7; 6 is the most isolated chunk — good candidate when a change of pace is needed.

## Sources

- [cloudogu/gitops-patterns](https://github.com/cloudogu/gitops-patterns) — repo structure patterns (LOW/community, corroborated by multiple sources)
- [Octopus: Structuring Argo CD repositories with ApplicationSets](https://octopus.com/blog/how-to-structure-your-argo-cd-repositories-using-application-sets)
- [mirceanton/external-dns-provider-mikrotik](https://github.com/mirceanton/external-dns-provider-mikrotik) — verified active (v1.6.3, June 2026); [benfiola/external-dns-routeros-provider](https://github.com/benfiola/external-dns-routeros-provider) alternative
- [external-dns webhook provider docs](https://kubernetes-sigs.github.io/external-dns/v0.15.0/) (official)
- [Sander0542/terraform-provider-nginxproxymanager](https://registry.terraform.io/providers/Sander0542/nginxproxymanager/latest/docs) — NPM API automation
- [NPM wildcard proxy-host issues #749](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/749), [#591](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/591) — unresolved ambiguity → spike flagged
- [Kubernetes Service docs](https://kubernetes.io/docs/concepts/services-networking/service/) — ExternalName limitations, services without selectors (official)
- [k3s networking docs](https://docs.k3s.io/networking/networking-services) — Traefik/ServiceLB defaults (official)
- Mikrotik WireGuard: [RouterOS docs](https://help.mikrotik.com/docs/display/ROS/WireGuard), [CHR+VPS guide (perlod)](https://perlod.com/tutorials/mikrotik-wireguard-setup-vps/), [Mikrotik forum — home server hosting via WG](https://forum.mikrotik.com/t/wireguard-setup-for-home-server-hosting/180290)
- cert-manager/Traefik wildcard homelab patterns: [Techno Tim](https://technotim.com/posts/kube-traefik-cert-manager-le/), [Stonegarden](https://blog.stonegarden.dev/articles/2023/12/traefik-wildcard-certificates/)

---
*Architecture research for: GitOps homelab deployment platform*
*Researched: 2026-07-07*
