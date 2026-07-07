# Pitfalls Research

**Domain:** GitOps homelab deployment platform (k3s on Proxmox, NPM reverse proxy, split DNS, LXC shared services)
**Researched:** 2026-07-07
**Confidence:** MEDIUM (web-verified against official docs, GitHub issues, and community post-mortems; cross-checked across multiple sources)

Phase names below are descriptive (the roadmap doesn't exist yet). Suggested phase buckets referenced throughout:
**P-Infra** (k3s VM + cluster provisioning), **P-GitOps** (ArgoCD/Flux + bootstrap + secrets), **P-Ingress** (DNS/NPM/TLS automation), **P-Services** (LXC shared services: Postgres/Redis/Debezium/NATS), **P-Scaffold** (per-project scaffolding tool + CI), **P-Public** (opt-in public exposure), **P-Ops** (backups/recovery hardening).

## Critical Pitfalls

### Pitfall 1: Split-DNS breaks cert-manager's DNS-01 self-check

**What goes wrong:**
Certificates get stuck in `propagation check failed` / "DNS record not yet propagated" forever. cert-manager creates the `_acme-challenge` TXT record in Cloudflare correctly, but never sees it, so it never tells Let's Encrypt to validate.

**Why it happens:**
cert-manager verifies TXT propagation using the recursive nameservers from the pod's `/etc/resolv.conf` — which in this setup chains to CoreDNS → the Mikrotik LAN DNS. The Mikrotik serves internal/authoritative-looking answers for `yourdomain.com` (that's the whole point of split DNS), so the public TXT record is invisible from inside the cluster. This is the single most common cert-manager failure in split-DNS homelabs (cert-manager issues #6572, #3234, #5917).

**How to avoid:**
Configure cert-manager with `--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53` **and** `--dns01-recursive-nameservers-only=true` (Helm values: `dns01RecursiveNameservers` / `dns01RecursiveNameserversOnly`). Bake this into the cluster bootstrap manifests from day one, not as a post-hoc fix.

**Warning signs:**
First `Certificate` sits `Ready: False` with an active `Challenge` for >10 minutes; challenge describe shows "propagation check failed"; `dig TXT _acme-challenge.myapp.domain.com @1.1.1.1` returns the record but the same query via cluster DNS doesn't.

**Phase to address:** P-Ingress (cert-manager install must include the flags; verify with a test cert before automating per-app certs).

---

### Pitfall 2: Debezium replication slot WAL bloat fills the Postgres LXC disk

**What goes wrong:**
Postgres WAL grows unbounded until the LXC disk is full, at which point Postgres panics and shuts down — taking every app database with it. This is the classic Debezium production killer, and it's *worse* on a low-traffic homelab, not better.

**Why it happens:**
A logical replication slot pins WAL until the consumer (Debezium) confirms it. Two homelab-specific triggers: (1) Debezium/NATS is down or misconfigured and nobody notices — the slot goes inactive but keeps retaining WAL for the **entire** database, not just tracked tables; (2) the tracked database is low-traffic, so Debezium never gets a chance to advance the confirmed LSN even while running (Gunnar Morling's "insatiable replication slot"). Also: slots survive connector deletion — deleting/recreating a Debezium connector during experimentation leaves an orphaned slot silently eating disk.

**How to avoid:**
- Set `heartbeat.interval.ms` on the connector plus a heartbeat action query (or rely on `pg_logical_emit_message()`, PG 14+) so the slot advances on low-traffic databases.
- Set `max_slot_wal_keep_size` in `postgresql.conf` (e.g. a few GB) as a hard safety net — slot invalidation forces a re-snapshot, which is annoying but far better than a down database.
- Write a runbook line: "if a Debezium connector is deleted, drop its slot: `SELECT pg_drop_replication_slot(...)`."
- Add `pg_replication_slots` lag to whatever minimal monitoring exists (even a cron + ntfy).

**Warning signs:**
`SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) FROM pg_replication_slots;` shows growing lag or `active = f`; `pg_wal/` directory growing steadily on the LXC.

**Phase to address:** P-Services (Debezium provisioning must ship with heartbeat + `max_slot_wal_keep_size` configured, not defaults).

---

### Pitfall 3: GitOps bootstrap chicken-and-egg — secrets needed before the secret machinery exists

**What goes wrong:**
The GitOps repo can't be fully declarative because the first sync needs secrets that don't exist yet: ArgoCD's repo credentials (if repo is private), the GHCR pull secret, the Cloudflare API token for cert-manager, and the sealed-secrets/SOPS decryption key itself. People either hand-apply secrets ad-hoc (undocumented, unreproducible — cluster rebuild fails months later) or commit plaintext secrets to git "temporarily" (forever).

**Why it happens:**
Every secret tool has the same recursion: sealed-secrets needs its controller running (and its private key restored on rebuild); External Secrets needs SecretStore credentials; SOPS needs the age key on the machine doing decryption. "The cluster is ephemeral and rebuildable" is only true if the bootstrap path is scripted.

**How to avoid:**
Pick ONE bootstrap ritual and script it. For a solo operator the simplest robust pattern: a single `bootstrap.sh` that (1) installs ArgoCD, (2) applies a small, well-known set of bootstrap secrets from an encrypted source (SOPS+age file in the repo, age key kept off-cluster in a password manager), (3) applies the root app-of-apps Application. Everything after that is GitOps. If using sealed-secrets instead: **back up the controller's private key immediately** — losing it makes every SealedSecret in git undecryptable, i.e., your "rebuildable" cluster isn't.

**Warning signs:**
Any `kubectl create secret` typed interactively that isn't recorded in the bootstrap script; a cluster-rebuild dry run that stalls asking "where does X credential come from?"

**Phase to address:** P-GitOps (define the bootstrap script + secret strategy before scaffolding any apps; test by rebuilding the k3s VM once — cheap insurance given the cluster is designed to be disposable).

---

### Pitfall 4: Double-proxy (NPM → Traefik/k3s ingress) breaks websockets, uploads, and forwarded headers

**What goes wrong:**
Apps deploy fine but misbehave subtly: websockets/SSE disconnect (T3 apps using tRPC subscriptions or Next.js HMR-ish live features), file uploads >1MB fail with 413, apps generate `http://` URLs or redirect-loop, and every request appears to come from NPM's IP (auth logs, rate limiting, Zitadel audit trails all useless).

**Why it happens:**
Two full nginx/traefik proxy layers each apply their own defaults: ingress-nginx's `proxy-body-size` default is **1m**; websockets need the Upgrade/Connection toggle enabled per NPM proxy host plus long read timeouts at *both* layers; NPM rewrites `X-Forwarded-Proto` on the inner hop (NPM issues #1556, #5216), and the k3s ingress doesn't trust NPM's `X-Forwarded-For` unless told to.

**How to avoid:**
Standardize the hop once, in the scaffolding templates, not per-app:
- NPM proxy host template: websockets ON, `client_max_body_size` raised (e.g. 100m+), pass `X-Forwarded-Proto $scheme`, `X-Forwarded-For $proxy_add_x_forwarded_for`.
- k3s ingress: configure trusted proxy IPs (Traefik `forwardedHeaders.trustedIPs` = NPM's IP) so headers propagate; set matching body-size/timeout defaults.
- Consider terminating TLS only at NPM and using plain HTTP to the ingress on the LAN (one TLS layer, simpler cert story inside) — decide once, document it.
- Include a websocket + 10MB-upload check in the end-to-end smoke test for the first app.

**Warning signs:**
413 errors on upload; websocket connections dropping at exactly 60s; app logs showing NPM's IP for all clients; OAuth redirect URIs generated as `http://`.

**Phase to address:** P-Ingress (proxy-hop contract), verified in the v1 success-gate app (P-Scaffold end-to-end test).

---

### Pitfall 5: Proxmox snapshots treated as Postgres backups

**What goes wrong:**
"Postgres is backed up — vzdump runs nightly." Then a restore is needed and the snapshot is crash-consistent at best (equivalent to yanking power) or, worse, the only copies live on the same single MS-01 that just died. Snapshot restore also restores the *whole* LXC — you can't recover one database or one table.

**Why it happens:**
Per-service LXC snapshots are the stated rationale for the one-LXC-per-service design, so it's natural to assume snapshots = backup. But snapshot backups of a database can cut transactions mid-flight (Proxmox forum guidance is explicit: pair snapshots with a consistent dump), and a single-node homelab has no second copy by default.

**How to avoid:**
- Nightly `pg_dump`/`pg_dumpall` (logical) inside or against the Postgres LXC, shipped **off the MS-01** (dev server, S3/B2, anywhere). Same idea for Redis (RDB copy), NATS JetStream (`store_dir` copy or stream backup), Zitadel (its Postgres).
- Keep vzdump snapshots too — they're great for fast whole-container rollback — just don't call them the backup.
- Test one restore before declaring v1 done.

**Warning signs:**
No backup artifact exists outside the MS-01; nobody has ever run a restore; backup job logs unchecked for weeks.

**Phase to address:** P-Ops (but the *decision* — logical dumps + off-host copy — should be recorded in P-Services so LXCs are provisioned with backup jobs from the start).

---

### Pitfall 6: Mikrotik regexp DNS entries shadow real DNS and don't behave like wildcards

**What goes wrong:**
A "wildcard" static entry like `.*\.domain\.com` on the Mikrotik silently hijacks *everything* under the domain — including apps intentionally made public (which should resolve to the AWS CHR path or be validated against public DNS), Cloudflare-hosted records like `_acme-challenge`, MX/verification records, etc. Or the regexp is written wrong (unescaped dots, uppercase) and matches nothing / too much intermittently.

**Why it happens:**
RouterOS has no true wildcard DNS — only regexp entries, which are lowercase-only, require escaping (`.*\.domain\.com$`), are slower than plain entries, and match with higher effective priority than forwarding to upstream. People copy a forum regexp and never audit what it swallows.

**How to avoid:**
Prefer **explicit per-app static entries** over a domain-wide regexp — this fits the platform perfectly, since the scaffolding tool creates the DNS entry per app anyway (Mikrotik REST API: `/ip/dns/static`). If a regexp catch-all is used, scope it to a dedicated subdomain level (e.g. `.*\.lab\.domain\.com`) and keep apex/public names out of it. Also: don't leave `allow-remote-requests=yes` reachable from WAN (open-resolver — firewall port 53 on the WAN interface), and remember clients using DoH (Firefox default, some IoT) bypass Mikrotik DNS entirely and will resolve public records instead.

**Warning signs:**
Public app resolves to the LAN NPM IP from inside the network when it should go through the public path (or vice versa); ACME TXT lookups behaving oddly (compounds Pitfall 1); `dig` from a phone on WiFi vs. cellular gives confusingly different results.

**Phase to address:** P-Ingress (DNS entry strategy decided when automating Mikrotik entries); P-Public (verify public/local resolution matrix per app).

---

### Pitfall 7: GHCR pull secret silently expires or lacks scope — deploys break weeks later

**What goes wrong:**
Everything works at setup; weeks later a new deploy hits `ImagePullBackOff: denied`. The fine-grained PAT used for the imagePullSecret expired (fine-grained PATs have mandatory expiry, max ~1 year), or the package is linked to a private repo and the token lacks `repo` scope, or a new app's package defaulted to private visibility while the pipeline assumed public.

**Why it happens:**
GHCR has no pull rate limits (unlike Docker Hub), so people assume auth is the easy part. But: private packages need a PAT with `read:packages` (+ `repo` if linked to a private repository); GHCR packages default to private on first push; token rotation is a human process with no reminder. Bonus trap: base images in Dockerfiles still come from Docker Hub and *are* rate-limited (200 pulls/6h unauthenticated per IP) — a cluster rebuild pulling many images can hit it.

**How to avoid:**
- Decide per-project default: public packages (no pull secret needed, simplest for a solo dev) vs. private (scaffolding must create/verify the pull secret).
- Use one long-lived classic PAT with `read:packages` only (or a dedicated machine-user), stored via the bootstrap secret path (Pitfall 3), referenced by a single namespace-replicated secret — not one token per app.
- Scaffolding should set package visibility explicitly (`gh api` or `packages: write` + visibility step in the workflow).
- Calendar reminder or check for token expiry; mirror/pin base images or authenticate Docker Hub pulls in CI.

**Warning signs:**
`ImagePullBackOff` on a *new* deploy while old pods run fine (cached image); GH Actions push succeeds (uses `GITHUB_TOKEN`) but cluster pull fails (uses PAT) — the asymmetry is the tell.

**Phase to address:** P-Scaffold (visibility + pull-secret handling in templates); P-GitOps (single pull secret in bootstrap).

---

### Pitfall 8: ArgoCD self-management + finalizers + auto-prune = accidental platform deletion

**What goes wrong:**
With app-of-apps, auto-sync, prune, and the `resources-finalizer.argocd.argoproj.io` finalizer everywhere, a bad git commit (renamed directory, botched ApplicationSet template, deleted YAML) cascades: ArgoCD prunes Applications, finalizers tear down all their child resources — ingresses, certs, PVCs — cluster-wide, from one push. If ArgoCD manages itself, a bad ArgoCD values change can also brick the thing that would fix it.

**Why it happens:**
Each feature is individually recommended ("Git as source of truth", "prune keeps the cluster clean", "finalizers make deletes work"), and together they remove every safety net. Homelabs adopt all of them at once because tutorials do.

**How to avoid:**
- Tier the sync policies: platform-critical apps (ArgoCD itself, cert-manager, ingress, sealed-secrets) get auto-sync **without prune** (or manual sync); leaf apps get full auto-sync+prune+selfHeal.
- Add finalizers deliberately per-app, not globally.
- Keep the root app-of-apps `kubectl apply`-able from the bootstrap script so ArgoCD can always be re-seeded.
- Remember the escape hatch: cluster is disposable by design — but only if Pitfall 3 (bootstrap) and Pitfall 5 (state outside) are actually solved.

**Warning signs:**
ArgoCD UI showing a wall of "Pruning" after a refactor commit; `argocd app list` shrinking unexpectedly; fear of touching the GitOps repo structure.

**Phase to address:** P-GitOps (sync-policy tiers defined when installing ArgoCD); revisit in P-Scaffold (what policy the scaffold stamps onto app manifests).

---

### Pitfall 9: Public exposure path leaks admin surfaces or ships apps with no auth

**What goes wrong:**
The AWS CHR → home → NPM path forwards by hostname; once the tunnel exists, *any* hostname NPM knows about is potentially reachable from the internet — including ArgoCD, NPM's own admin UI (port 81), Traefik dashboard, or an app that was "local-only by default" but got a public DNS record by accident. Internet scanners find admin panels within hours; NPM's admin UI and ArgoCD both have had exploited CVEs.

**Why it happens:**
Split DNS makes local and public hostnames look identical (`myapp.domain.com` everywhere), so the only thing separating "local-only" from "public" is which resolver answers and what the CHR forwards — easy to get wrong when the same NPM instance serves both. Opt-in public exposure done by hand ("just add the Cloudflare record") skips the auth question.

**How to avoid:**
- Make the public path deny-by-default at the **edge**: CHR forwards only to an explicit allowlist (or NPM uses a separate public-facing entry that only routes explicitly-flagged hosts). A default-vhost 444/blackhole in NPM for unknown hostnames on the public path.
- Scaffolding's `public: true` flag should require an auth decision: app has its own auth (Zitadel/NextAuth) or gets an SSO gate (oauth2-proxy/Authelia against the existing Zitadel) — never "public and open."
- Never route ArgoCD, NPM admin (81), Proxmox, or Traefik dashboard through the public path; keep them LAN/VPN-only. Verify with an external scan (nmap from the AWS box, or a phone on cellular) after enabling public ingress.

**Warning signs:**
Fetching `https://argocd.domain.com` from cellular data returns a login page instead of a timeout; NPM access logs showing bot paths (`/wp-login.php`, `/.env`) on hosts you thought were local-only.

**Phase to address:** P-Public (edge allowlist + auth requirement is the core design of this phase, not an afterthought).

---

### Pitfall 10: LXC memory limits OOM-kill Postgres; NATS JetStream defaults lose data

**What goes wrong:**
Two flavors of the same "defaults are wrong in containers" problem: (a) Postgres inside an LXC hits the cgroup memory ceiling and gets OOM-killed mid-write — no graceful degradation, and tools inside the LXC often mis-read available memory (seeing host RAM), so `shared_buffers`/`work_mem` get sized against 64GB when the LXC has 4GB. (b) NATS JetStream's default `store_dir` is under `/tmp` — streams silently vanish on LXC reboot; no `max_store`/stream `max_bytes` means a runaway publisher fills the disk.

**Why it happens:**
Native-binary-in-LXC (correctly chosen here over Docker-in-LXC) means *you* are the operator setting every limit; distro defaults assume bare metal. Homelab guides mostly cover the install, not the sizing.

**How to avoid:**
- Postgres: size `shared_buffers` (~25% of the **LXC's** memory limit), set the LXC memory with headroom above expected Postgres usage, and prefer a modest swap allocation on the LXC so pressure degrades before OOM.
- NATS: set `store_dir` to a real persistent path, `max_store` reflecting actual allocated disk, per-stream `max_bytes`/`max_age`, file storage (not memory) for anything that must survive restart; keep 15–25% disk headroom above the sum of stream reservations.
- Redis: set `maxmemory` + eviction policy explicitly; without it Redis grows until the cgroup kills it.
- Budget the whole MS-01 up front (see Performance Traps) so LXC limits + k3s VM + Proxmox overhead actually fit.

**Warning signs:**
`dmesg`/journal on the Proxmox host showing oom-killer events for the LXC's cgroup; Postgres logs with "server process was terminated by signal 9"; JetStream streams empty after a container restart.

**Phase to address:** P-Services (provisioning templates for each LXC include explicit memory/disk/config limits).

---

### Pitfall 11: Over-engineering the platform before one app ships

**What goes wrong:**
The platform grows Crossplane, Vault, service mesh, multi-env ApplicationSets, Renovate, and a bespoke CLI framework — and six months in, zero apps are deployed and every component is a maintenance liability for one person. Alternatively, the scaffolding tool becomes a "platform product" with plugins before it has scaffolded its second project.

**Why it happens:**
GitOps content is written by and for platform teams at companies; copying their reference architectures imports their org-scale problems. Solo homelabs have effectively unlimited "requirements" and no external forcing function.

**How to avoid:**
The project already has the right success gate — **one real app live end-to-end**. Enforce it: any component that isn't on the critical path of "push → build → deploy → resolve → TLS" is deferred (this matches the stated out-of-scope list: no monitoring stack, no HA, no self-hosted registry in v1). Scaffolding v1 = copy templates + string substitution + git commit; no plugin system. Prefer boring: sealed-secrets or SOPS over Vault; plain Application manifests over ApplicationSets until app #3 exists.

**Warning signs:**
Roadmap phases that don't mention an app; comparing secret managers for the second week; the scaffold tool has a config file schema before it has generated one project.

**Phase to address:** All phases — but concretely, roadmap construction: every phase should end with a demonstrable step toward the v1 gate app.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hand-applied secrets ("I'll GitOps-ify it later") | Unblocks today | Cluster rebuild fails; undocumented state | Never — record every secret in the bootstrap path the day it's created |
| Manual NPM proxy host / Mikrotik DNS entry for one app | Faster than automating | Per-app drift; automation never gets validated; "works for app 1, breaks for app 5" | OK for the *first* app only, if replaced by automation before app #2 |
| One wildcard cert for `*.domain.com` shared everywhere | One cert to manage | Single key compromise exposes all hostnames; NPM/k3s cert duplication confusion | Acceptable for a solo homelab if the key stays in one place (NPM), documented |
| vzdump snapshots as the only backup | Zero extra tooling | Crash-consistent only; all copies on the dying host | Never for Postgres/Zitadel; fine for stateless LXCs |
| `latest` tag + `imagePullPolicy: Always` instead of digest/SHA tags | Simpler CI | Non-reproducible deploys; ArgoCD can't diff; rollback is guesswork | Never — scaffold should stamp git-SHA tags from day one |
| Skipping resource requests/limits on app pods | Apps schedule easily | One leaky app starves the single-node cluster; kubelet evictions look like platform bugs | MVP-only; add defaults to the scaffold template early |
| Running ArgoCD with the initial admin password, no SSO | Faster setup | Shared static credential; no audit; painful to fix later | Acceptable for LAN-only v1; wire Zitadel OIDC in a later phase (it's already running) |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Cloudflare (cert-manager) | Global API Key, or token missing `Zone → Zone → Read` | Scoped API token: `Zone.DNS:Edit` + `Zone.Zone:Read`, restricted to the one zone |
| Cloudflare (public DNS) | Proxied (orange-cloud) record pointing at the AWS CHR while expecting raw TCP forward / non-HTTP traffic | Decide proxied vs. DNS-only explicitly per record; DNS-only for the CHR path unless Cloudflare proxying is a deliberate layer |
| Mikrotik REST API (scaffold automation) | Using the admin account over HTTP for automation | Dedicated API user with a policy limited to DNS writes, HTTPS (`www-ssl`) only |
| GHCR | Assuming package inherits repo visibility; token without `repo` scope for private-repo packages | Set package visibility explicitly in CI; PAT with `read:packages` (+`repo` if needed) |
| GitHub Actions → GitOps repo | CI pushes manifest bumps to the same branch ArgoCD watches with no concurrency control | Use a distinct GitOps repo (or path) with CI committing image-tag bumps via a serialized job; or use ArgoCD Image Updater and skip CI-side bumps |
| Zitadel (existing LXC) | Apps hardcode LAN IP; redirect URIs registered as `http://` | Use the split-DNS hostname with valid TLS (Zitadel behind NPM too); register `https://` redirect URIs; treat Zitadel as untouchable prod (it's the one pre-existing stateful service) |
| k3s ↔ LXC services | Relying on IPs; Postgres `pg_hba.conf`/`listen_addresses` defaults blocking the k3s VM subnet | DNS names for service endpoints (Mikrotik static entries); explicitly allow the k3s VM/pod SNAT address range in `pg_hba.conf`; remember pods egress with the VM's IP |
| AWS Mikrotik CHR | Forwarding all :443 to home NPM (full exposure), no fail-closed behavior | Explicit per-host/per-port forward rules; default-drop; consider WireGuard tunnel home rather than raw dst-nat |

## Performance Traps

Patterns that work at small scale but fail as usage grows. Scale here = number of apps/services on one MS-01, not users.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No RAM budget across Proxmox + k3s VM + LXCs | Host swapping/OOM; random LXC kills; k3s VM feels slow | Write the budget once: e.g. (assuming 64GB MS-01) host ~4GB, k3s VM 16–24GB, Postgres 4–8GB, Redis 2GB, NATS 2GB, Debezium (JVM!) 2–4GB, Zitadel 2GB, headroom ~20% | The day Debezium (JVM, ~1GB+ baseline) joins an already-full host |
| k3s single VM sized like "just an app server" | Pods `Pending`; kubelet `MemoryPressure` evictions | k3s server + Traefik + CoreDNS + ArgoCD (repo-server spikes during syncs) eat ~2–4GB before any app; size VM ≥8GB min, 16GB comfortable; disable unused bundled bits (e.g. `--disable traefik` only if replacing it — otherwise keep defaults) | ~5–10 T3 apps with default Node memory footprints |
| ArgoCD polling many app repos every 3 min | repo-server CPU spikes; sync lag | Monorepo for GitOps manifests (one repo to poll) + webhook from GitHub instead of polling | Dozens of Applications each pointing at separate repos |
| ZFS/storage on single NVMe with DB WAL + JetStream + k3s images | I/O latency spikes; etcd/sqlite (k3s) timeouts | Separate the noisy writers if possible (second NVMe in MS-01); at minimum monitor iowait; keep JetStream off any network storage | Debezium snapshot of a large table concurrent with image pulls |
| Every request hopping NPM → Traefik → pod with TLS at both hops | Noticeable latency, double CPU for TLS | Terminate TLS once at NPM; HTTP over LAN to ingress (documented decision) | Not a v1 problem; matters with websocket-heavy apps |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| ArgoCD / NPM admin (:81) / Proxmox / Traefik dashboard reachable via the public path | Full platform compromise from one scanned CVE or brute-forced login | Admin surfaces LAN/VPN-only; public path is an explicit allowlist at the CHR/NPM; verify from cellular after every public-exposure change |
| `public: true` apps shipped without auth | Data exposure; app becomes a bot playground | Scaffold makes auth a required field for public apps (own auth or Zitadel-backed SSO gate) |
| Cloudflare API token with account-wide or Global Key powers stored in-cluster | Token theft = full DNS takeover (and cert issuance) for the domain | Zone-scoped token (Pitfall/Integration above); stored via the bootstrap secret path; rotate if ever pasted anywhere |
| Mikrotik with `allow-remote-requests=yes` and no WAN input filter on :53 | Open resolver — DDoS amplification participant; ISP abuse reports | WAN input chain drops UDP/TCP 53 (both home router and AWS CHR) |
| GHCR PAT with `write:packages` (or `repo`) used as the cluster pull secret | Leaked kubeconfig/secret = attacker can push images your cluster will run | Pull secret uses a read-only token (`read:packages` only); write tokens live only in GitHub Actions |
| Secrets committed plaintext "temporarily" during bootstrap | Git history is forever; GHCR/Cloudflare/DB creds leaked on repo publication | SOPS/sealed-secrets from commit #1; pre-commit secret scanner (gitleaks) in the GitOps repo |
| Trusting `X-Forwarded-For` from any source at the ingress | IP-based allowlists/rate limits spoofable by any client setting the header | Ingress trusts XFF only from NPM's IP; NPM overwrites (not appends) client-supplied XFF at the edge |
| AWS CHR dst-NAT'ing broad port ranges home | Home LAN becomes internet-adjacent; lateral movement path | Tunnel (WireGuard) + explicit per-service forwards; CHR firewall default-drop; keep CHR RouterOS patched (public-facing Mikrotiks are heavily targeted) |

## UX Pitfalls

"User" here = the solo operator using the platform in six months, having forgotten everything.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Scaffold generates files but doesn't say what happens next | Operator stares at repo wondering why app isn't live | Scaffold ends with a printed checklist: what was created, what URL to watch (ArgoCD app), expected time-to-live |
| Silent multi-system failure (DNS created, NPM failed, cert pending) | "It's broken" with 4 systems to check by hand | Scaffold (or a `status` subcommand) verifies each link: DNS resolves → NPM host exists → cert Ready → ingress 200 |
| No teardown path | Dead apps accumulate DNS entries, NPM hosts, certs, namespaces | `scaffold destroy` (or documented delete ritual) from day one — reverse of create, including Mikrotik/NPM cleanup |
| Naming drift (`myapp` vs `my-app` vs repo name) across DNS/NPM/k8s/GHCR | Debugging requires a mental mapping table | Scaffold derives ALL names from one slug; validation rejects non-conforming names |
| Bootstrap knowledge lives in shell history | Rebuild after failure = archaeology | `bootstrap.sh` + a RUNBOOK.md maintained as part of P-GitOps, tested by an actual rebuild |

## "Looks Done But Isn't" Checklist

- [ ] **cert-manager:** Cert shows Ready — verify it *renews*: check the ClusterIssuer works with recursive-nameserver flags, not a hand-issued cert imported into NPM.
- [ ] **Websockets through both proxies:** Page loads fine — verify a live websocket (tRPC subscription / `wscat`) stays up >60s through NPM → ingress.
- [ ] **Uploads:** Small POSTs work — verify a 10MB+ upload passes both proxy layers (413 is the failure mode).
- [ ] **GitOps rebuild:** ArgoCD syncs — verify by destroying and re-bootstrapping the k3s VM once; time it. "Disposable cluster" is a claim until tested.
- [ ] **Backups:** Dump job runs — verify a restore into a scratch LXC actually produces a working database, and the dump exists off the MS-01.
- [ ] **Debezium:** Events flow — verify the slot advances during a 24h idle period (heartbeat working) and check `pg_replication_slots` lag.
- [ ] **Split DNS:** Works on your laptop — verify from a phone on WiFi (uses DHCP DNS?), a DoH-enabled browser, and cellular (public path or NXDOMAIN as intended).
- [ ] **Public exposure:** App reachable — verify what *else* is reachable: scan the CHR public IP from outside; confirm admin UIs time out.
- [ ] **Pull secrets:** First deploy works — verify a fresh namespace + brand-new private image pulls (tests the secret, not the node's image cache).
- [ ] **k3s reboot:** Cluster runs — verify the whole MS-01 survives a power cycle: LXC start order (Postgres before Debezium/apps), k3s VM autostart, NPM up before cert renewals.

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| WAL disk full (Debezium slot) | MEDIUM | Free space (delete non-WAL files/extend disk) → restart Postgres → `pg_drop_replication_slot` if slot invalidated → fix heartbeat/`max_slot_wal_keep_size` → Debezium re-snapshot |
| Sealed-secrets key lost | HIGH | No decryption possible: re-create every secret from the upstream sources (password manager, provider dashboards), re-seal all. Prevent: key backup at install |
| ArgoCD pruned the platform (bad commit) | MEDIUM | Revert the git commit → re-apply root app from bootstrap script → resync. State (LXCs) is untouched by design — this is why state-outside-k3s pays off |
| Cert issuance broken (token/propagation) | LOW | Apps stay up on existing certs ~30–60 days; fix token scopes / recursive-nameserver flags; `cmctl renew` to force |
| Postgres LXC corrupted / host disk dies | HIGH | Restore latest logical dump into fresh LXC (this is why dumps must live off-host); re-point DNS entry; re-create Debezium slots/connectors; accept data loss since last dump |
| Admin UI found exposed | MEDIUM | Remove forward rule at CHR/NPM immediately → rotate that service's credentials/sessions → audit access logs → add the external-scan verification step |
| GHCR pull secret expired mid-incident | LOW | Regenerate PAT → update the one shared secret → `kubectl rollout restart` affected deploys; add expiry reminder |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. DNS-01 self-check vs split DNS | P-Ingress | Issue a test cert end-to-end with split DNS active; check Challenge events clean |
| 2. Debezium WAL bloat | P-Services | 24h idle-slot lag check; `max_slot_wal_keep_size` set; runbook entry exists |
| 3. Bootstrap chicken-and-egg | P-GitOps | Rebuild k3s VM from `bootstrap.sh` only; zero interactive `kubectl create secret` |
| 4. Double-proxy websockets/uploads/headers | P-Ingress + P-Scaffold | Smoke test: websocket >60s, 10MB upload, client IP visible in app logs |
| 5. Snapshot-only Postgres backups | P-Services (decision) / P-Ops (implementation) | Restore drill from an off-host dump into scratch LXC |
| 6. Mikrotik regexp DNS shadowing | P-Ingress | Resolution matrix test: local host, public host, non-existent host — from LAN, DoH browser, cellular |
| 7. GHCR pull secret scope/expiry | P-Scaffold | Fresh-namespace private-image pull test; documented token scope + expiry policy |
| 8. ArgoCD prune/finalizer cascade | P-GitOps | Sync-policy tiers documented; simulate a "deleted directory" commit against a leaf app only |
| 9. Public exposure of admin/no-auth apps | P-Public | External port/vhost scan from off-network; scaffold refuses `public: true` without auth choice |
| 10. LXC OOM / JetStream defaults | P-Services | Written RAM/disk budget for the MS-01; each LXC config sets memory/`store_dir`/`max_store`/`maxmemory` explicitly |
| 11. Over-engineering | Roadmap construction | Every phase's exit criterion references progress toward the v1 gate app |

## Sources

- cert-manager docs — [Cloudflare DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/), [DNS-01 recursive nameservers](https://cert-manager.io/docs/configuration/acme/dns01/); issues [#6572](https://github.com/cert-manager/cert-manager/issues/6572), [#3234](https://github.com/cert-manager/cert-manager/issues/3234), [#5917](https://github.com/cert-manager/cert-manager/issues/5917), [#4624](https://github.com/cert-manager/cert-manager/issues/4624) — MEDIUM confidence (official docs + reproduced issues)
- Nginx Proxy Manager issues — [#1556 X-Forwarded headers](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/1556), [#5216 SSL redirect in proxy chains](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/5216), [#5374 XFF/Real-IP for ACLs](https://github.com/NginxProxyManager/nginx-proxy-manager/issues/5374); [Authelia discussion #4627](https://github.com/authelia/authelia/discussions/4627) — MEDIUM
- MikroTik — [RouterOS DNS docs](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS) (regexp escaping, lowercase, performance; allow-remote-requests), [forum: wildcard DNS](https://forum.mikrotik.com/viewtopic.php?t=167949), [forum: hairpin NAT](https://forum.mikrotik.com/viewtopic.php?t=180446) — MEDIUM
- ArgoCD — [Secret Management docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/), [Octopus: finalizer pitfalls](https://octopus.com/blog/argocd-application-deletion-finalizers), [Codefresh: finalizers](https://codefresh.io/blog/argocd-application-deletion-finalizers/), [app-of-apps deletion discussion #12209](https://github.com/argoproj/argo-cd/discussions/12209), [ArgoCD managing itself](https://sofianedjerbi.com/en/blog/argocd-manage-itself/), [SOPS+age with sealed-secrets bootstrap](https://www.jonashietala.se/blog/2026/05/31/sops_age_and_sealed_secrets/) — MEDIUM
- GHCR — [rate limits discussion #49671](https://github.com/orgs/community/discussions/49671), [pull secrets discussion #160722](https://github.com/orgs/community/discussions/160722), [GHCR with Kubernetes](https://dev.to/asizikov/using-github-container-registry-with-kubernetes-38fb), [GHCR traffic/spending limits](https://blog.cloud-eng.nl/2023/01/23/ghcr-acr-traffic/) — MEDIUM
- Postgres/Proxmox — [Proxmox forum: snapshot consistency](https://forum.proxmox.com/threads/considerations-regarding-snapshot-backup-consistency.1000/), [pct docs](https://pve.proxmox.com/pve-docs/chapter-pct.html), [Postgres on dedicated LXC](https://metasora.com/blog/postgres-dedicated-lxc-docker/), [LXC resource limits/OOM](https://proxmoxpulse.com/articles/proxmox-lxc-resource-limits/) — MEDIUM
- Debezium/Postgres CDC — [Debezium Postgres connector docs](https://debezium.io/documentation/reference/stable/connectors/postgresql.html), [Morling: insatiable replication slot](https://www.morling.dev/blog/insatiable-postgres-replication-slot/), [Morling: mastering replication slots](https://www.morling.dev/blog/mastering-postgres-replication-slots/), [Zalando: fixing logical replication at scale](https://engineering.zalando.com/posts/2025/12/contributing-to-debezium.html), [Streamkap: slot issues](https://streamkap.com/resources-and-guides/debezium-replication-slot-issues) — MEDIUM (multiple independent authoritative sources)
- NATS — [JetStream docs](https://docs.nats.io/nats-concepts/jetstream), [server configuration](https://docs.nats.io/running-a-nats-service/configuration), [Synadia: storage exhaustion](https://www.synadia.com/insights/checks/nats-jetstream-storage-utilization-critical), [Synadia: memory streams](https://www.synadia.com/insights/checks/nats-memory-storage-large-stream) — MEDIUM
- Homelab exposure — [HomelabAddiction security guide](https://homelabaddiction.com/homelab-security/), [readthemanual: zero-trust before going public](https://readthemanual.co.uk/secure-your-homelab-2025/) — LOW-MEDIUM (community guidance, consistent across sources)

---
*Pitfalls research for: GitOps homelab deployment platform (k3s/Proxmox/NPM/Mikrotik/Cloudflare)*
*Researched: 2026-07-07*
