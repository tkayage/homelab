# Feature Research

**Domain:** GitOps-based homelab deployment platform (solo-operator internal developer platform: k3s on Proxmox, per-app DNS/proxy/TLS, shared stateful LXC services)
**Researched:** 2026-07-07
**Confidence:** MEDIUM (community consensus from reference homelab repos, vendor docs, and practitioner blogs; verified across multiple independent sources — no single authoritative spec for this domain exists)

## Feature Landscape

Reference class: public k3s+ArgoCD homelab repos (cterence/homelab-gitops, loeken/homelab, pablodelarco/kubernetes-homelab, adavarski/homelab), self-hosted PaaS products (Coolify, Dokploy, CapRover), and GitOps vendor guidance (Argo CD docs, Codefresh/Octopus environment-modeling guides). The consistent bar users measure against is "Heroku-at-home": push code, get a URL with valid TLS.

### Table Stakes (Users Expect These)

Missing any of these and the platform fails its own core value ("push to git → app is live, no manual wiring").

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Git push → image build → deploy pipeline | The entire point; every comparable platform (Coolify, Dokploy, any GitOps repo) has this | MEDIUM | GitHub Actions builds → GHCR → tag written to GitOps repo (CI-writes-tag is the simplest closure of the loop; ArgoCD Image Updater is the alternative) |
| GitOps engine with auto-sync, self-heal, prune | Standard ArgoCD/Flux posture in every reference homelab; without prune, deleted apps linger | LOW | Install + one AppProject/ApplicationSet config. Note: manual UI rollback is blocked while auto-sync is on — rollback story is "git revert" (see below) |
| Automatic valid TLS per app | "Valid cert without opening ports" is a solved problem (cert-manager or NPM native, both via Cloudflare DNS-01); browser warnings = platform feels broken | LOW–MEDIUM | A **wildcard cert** (`*.domain.com`) issued once via DNS-01 collapses per-app cert issuance to zero work. Decide cert termination point (NPM vs k3s ingress) early — doing both is redundant |
| Automatic hostname + reverse proxy wiring per app | The Kubernetes-standard contract is "add an Ingress, get a URL" (ExternalDNS + ingress annotations); users expect zero manual router/NPM clicks per app | MEDIUM | **Key simplification:** one wildcard static DNS entry on Mikrotik (`*.domain.com` → NPM) + one wildcard NPM proxy host → k3s ingress routes by Host header. This reduces per-app wiring to "scaffold emits an Ingress manifest" — no Mikrotik/NPM API automation needed at all. Per-app API automation (RouterOS API + NPM REST API) is the fallback if wildcards are rejected |
| One-command app scaffolding | Per PROJECT.md this is the only allowed per-project manual step; comparable to `coolify` app creation or Backstage templates | MEDIUM | CLI renders Dockerfile/CI workflow into the app repo + manifests folder into the GitOps repo. ApplicationSet **git directory generator** means dropping the folder in = registered; no per-app Application resource to manage |
| Secrets safely in git | Can't scaffold a T3 app without DATABASE_URL/AUTH_SECRET; plaintext in git is disqualifying | MEDIUM | SOPS+age or External Secrets Operator fit the "disposable cluster" decision better than Sealed Secrets (whose decryption key lives *in* the cluster — lose cluster, lose secrets). Blocks: GHCR pull secret, Cloudflare token, DB creds |
| Health checks + safe rollback path | ArgoCD health status is built in; users expect a failed deploy to be visible and revertible | LOW | Scaffold must emit readiness/liveness probes or ArgoCD reports Healthy on broken apps. Rollback = `git revert` + auto-sync; document this, don't build machinery |
| Deployment visibility (ArgoCD UI) | Comes free with ArgoCD; every reference repo exposes it | LOW | ArgoCD UI itself should be the first "app" wired through the DNS/proxy/TLS path — it dogfoods the platform |
| Apps reach shared LXC services | Active requirement; a platform where apps can't reach Postgres is dead | LOW | LAN routing + per-app connection Secret. Convention: service DNS names resolvable from cluster (CoreDNS custom entries or Mikrotik DNS) |
| GHCR image pull | Chosen registry; private images need pull secrets in each app namespace | LOW | Scaffold or a cluster-wide secret replicator handles this; depends on secrets management |

### Differentiators (Competitive Advantage)

Aligned with the core value: reducing per-app marginal effort toward zero. These are what make this *a platform* rather than *a cluster with apps on it*.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-app DB/user provisioning in shared Postgres | Heroku-grade DX: scaffold flag → database + role + credentials Secret exist; removes the last manual step for T3 apps | MEDIUM | movetokube/postgres-operator is purpose-built for **external** Postgres (CRDs create db+user on the LXC server, emit a k8s Secret). Alternative: scaffold-time psql script — simpler, no operator to run, but imperative. Operator keeps it declarative/GitOps-native |
| Opt-in public exposure flag | `--public` at scaffold time → Cloudflare DNS record → AWS CHR path; local-first security by default with one-flag escape hatch | MEDIUM | Required (Active) in PROJECT.md but the *one-flag DX* is the differentiator vs manually adding a Cloudflare record. Cloudflare API call is trivial; CHR→NPM forwarding is one-time infra, not per-app |
| Deployment notifications (push to phone/chat) | Solo operator isn't watching the ArgoCD UI; "your push is live" / "sync failed" closes the feedback loop | LOW | argocd-notifications → ntfy (homelab favorite, self-hosted, phone push) or Discord webhook. Very high value-to-effort ratio |
| Homepage dashboard auto-discovery | gethomepage reads `gethomepage.dev/*` Ingress annotations — scaffolded apps appear on a service directory automatically, with pod status | LOW | Pure convention: scaffold template includes the annotations. Zero ongoing cost once the dashboard runs |
| App decommissioning (`scaffold remove`) | Platforms accrete zombie apps; clean teardown (manifests, DNS record if public, DB archived, NPM host if non-wildcard) is almost always forgotten | LOW–MEDIUM | With prune enabled + wildcard DNS, teardown is mostly "delete the folder" — the tool just needs to also handle public DNS records and DB retirement |
| Zitadel OIDC client auto-provisioning | `--auth` scaffold flag creates an OIDC client in Zitadel and injects client id/secret — auth becomes as zero-touch as DNS | MEDIUM–HIGH | Zitadel has a management API and Terraform provider. High wow-factor for T3 apps (NextAuth), but defer past v1 |
| Renovate on the GitOps repo | Keeps platform Helm charts and app base images patched via PRs; the "maintenance autopilot" for a solo operator | LOW | Hosted Renovate app is free for GitHub; recommended over ArgoCD Image Updater for chart/dependency updates |
| Staging overlay per app (opt-in) | Kustomize overlay + `myapp-staging.domain.com` for risky changes; folder-based promotion (copy tag from staging to prod dir) | MEDIUM | Only worth it as opt-in; solo homelabs overwhelmingly run single-env per app. Model environments as folders, not branches (Codefresh/Argo guidance) |

### Anti-Features (Commonly Requested, Often Problematic)

The community failure mode is documented repeatedly: production-grade tooling turns a solo homelab into "a second job keeping the platform healthy." PROJECT.md's own Out of Scope list already reflects this; research confirms and extends it.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-node HA / distributed storage (Longhorn, Ceph) | "Production-like", resume-driven | One physical MS-01 = zero real redundancy; distributed storage on one host is pure overhead and a top regret in homelab retrospectives | Single k3s VM; Proxmox snapshots; state in LXCs |
| Velero + MinIO/S3 backup stack | "Kubernetes backup best practice" | Designed to protect in-cluster state — this design deliberately has none; MinIO alone is heavier than the problem | GitOps repo *is* the cluster backup (rebuild ≈ 30 min: k3s + ArgoCD + sync); Proxmox vzdump for LXCs + scheduled pg_dump for Postgres |
| In-cluster DB operators (CloudNativePG) | Slick declarative DBs | Puts state back inside the disposable cluster, defeating the core architectural decision | Shared Postgres LXC + external-Postgres operator (movetokube) for per-app provisioning |
| Backstage / full IDP portal | "Real platform engineering" | Backstage is a full-time product to run; absurd overhead for one developer | A scaffold CLI + gethomepage covers 100% of the solo-use surface |
| Per-PR preview environments | Modern team DX (ApplicationSet PR generator) | Real infra + teardown management on a single node; benefits accrue to *reviewers*, and there are none | Run locally during dev; optional staging overlay later. Revisit only if collaboration starts |
| Service mesh (Istio/Linkerd) | mTLS, observability buzz | Most-cited homelab overkill item; nothing here needs it | LAN + NetworkPolicies if isolation is ever needed |
| Self-hosted container registry | Independence from GitHub | Another stateful service to run, back up, and secure; already ruled out | GHCR (free, integrated with Actions) |
| Full observability stack (Prometheus/Grafana/Loki) at v1 | "You need monitoring" | Heavyweight before any app exists; already deferred in PROJECT.md | ArgoCD health + notifications + gethomepage status now; monitoring as its own later milestone |
| Imperative deploy CLI (`platform deploy`) | Feels fast and direct | Splits the source of truth; drift between CLI state and git state is the classic GitOps failure | Git push is the only deploy verb; scaffold is the only CLI |
| Per-app Mikrotik/NPM API automation (if wildcard works) | "Automate everything" | Building and maintaining custom API glue (RouterOS + NPM's semi-documented REST API) for a problem a single wildcard DNS entry + wildcard cert solves statically | Wildcard-first: `*.domain.com` → NPM → k3s ingress; per-app routing via Ingress Host rules. Only build API glue for the opt-in public path (Cloudflare) |

## Feature Dependencies

```
[Scaffolding CLI]
    └──requires──> [GitOps engine + ApplicationSet directory generator]
    └──requires──> [Manifest templates (Deployment/Service/Ingress/probes)]
    └──requires──> [Secrets management]          (DB creds, app env)
    └──requires──> [CI pipeline template → GHCR]

[Automatic hostname/proxy/TLS per app]
    └──requires──> [Wildcard DNS on Mikrotik + wildcard NPM proxy host + wildcard cert (DNS-01)]   (one-time)
    └──requires──> [k3s ingress controller routing by Host]

[Per-app DB provisioning] ──requires──> [Postgres LXC] and [Secrets management]
[Opt-in public exposure] ──requires──> [Local exposure path working] and [Cloudflare API token] and [AWS CHR → NPM forwarding (one-time)]
[GHCR private pulls] ──requires──> [Secrets management]

[Deployment notifications] ──enhances──> [GitOps engine]
[Homepage auto-discovery] ──enhances──> [Scaffolding CLI]   (annotations baked into Ingress template)
[App decommissioning] ──enhances──> [Scaffolding CLI]       (requires prune enabled)
[Zitadel OIDC provisioning] ──enhances──> [Scaffolding CLI]
[Staging overlays] ──enhances──> [Scaffolding CLI]

[Velero backup] ──conflicts──> [State-outside-cluster decision]
[Preview environments] ──conflicts──> [Single-node resource budget]
[Imperative deploy CLI] ──conflicts──> [GitOps as sole deploy interface]
```

### Dependency Notes

- **Scaffolding requires everything else first:** the CLI is the *last* thing to build well — it merely emits conventions that the platform (GitOps engine, ingress path, secrets) must already honor. Roadmap implication: platform rails before scaffold polish, but a crude scaffold (copy a template folder) works from day one via the ApplicationSet directory generator.
- **Wildcard-first collapses the hardest table stake:** if Mikrotik wildcard static DNS + NPM wildcard host + wildcard cert are validated early (a one-day spike), "automatic DNS/proxy/TLS per app" drops from MEDIUM-complexity custom API automation to zero marginal work per app. This spike should happen before committing to any per-app API glue. (Caveat to verify: Mikrotik static DNS wildcard/regex entry behavior, and NPM wildcard host header pass-through — flagged for phase research, LOW confidence on specifics.)
- **Secrets management is the bottleneck dependency:** GHCR pulls, Cloudflare tokens, DB credentials, and app env all block on it. It must land in the first platform phase. Sealed Secrets conflicts philosophically with the disposable-cluster decision (in-cluster private key); SOPS+age or ESO preserve rebuildability.
- **DB provisioning depends on secrets *and* the Postgres LXC**, so it naturally sits a phase after both.
- **Public exposure is additive**, not structural: local path first; the public flag only adds a Cloudflare record on top (per-app) plus one-time CHR plumbing.

## MVP Definition

### Launch With (v1)

Matches PROJECT.md's success gate: one real app live end-to-end.

- [ ] k3s VM + ArgoCD with auto-sync/self-heal/prune + ApplicationSet directory generator — the deployment engine
- [ ] CI template: build → GHCR → write tag to GitOps repo — closes push-to-live loop
- [ ] Wildcard exposure rail: Mikrotik wildcard DNS → NPM wildcard proxy → k3s ingress; wildcard TLS via Cloudflare DNS-01 — zero-touch per-app URLs
- [ ] Secrets management (SOPS+age or ESO) — blocks GHCR pulls, tokens, app env
- [ ] Scaffold CLI v1: render app manifests (with probes + homepage annotations) into GitOps repo + CI workflow into app repo — the one manual step
- [ ] Shared-service LXCs (Postgres at minimum) reachable from cluster, connection via Secret — T3 apps need a database
- [ ] Opt-in public exposure (even if v1 = scaffold flag that creates the Cloudflare record; CHR forwarding as one-time setup) — Active requirement
- [ ] One real T3 app deployed end-to-end — the validation gate

### Add After Validation (v1.x)

- [ ] Per-app DB/user auto-provisioning (movetokube operator or scaffold-time script) — trigger: second app deployed, manual `CREATE DATABASE` gets old immediately
- [ ] Deployment notifications via argocd-notifications → ntfy/Discord — trigger: first silent failed sync
- [ ] gethomepage dashboard consuming scaffold annotations — trigger: more than ~3 apps running
- [ ] `scaffold remove` decommissioning — trigger: first retired app
- [ ] Renovate on GitOps repo — trigger: first stale-chart security itch

### Future Consideration (v2+)

- [ ] Zitadel OIDC client auto-provisioning (`--auth` flag) — defer: valuable but touches an external API and auth flows; not needed to prove the platform
- [ ] Opt-in staging overlays + folder-based promotion — defer: solo dev, single env per app is the norm; add when a change actually scares you
- [ ] Observability stack (Prometheus/Grafana/Loki) — defer: explicit future milestone in PROJECT.md
- [ ] Preview environments (ApplicationSet PR generator) — defer: revisit only if collaborators appear
- [ ] Remaining shared-service LXCs (Debezium, NATS+JetStream) wired into scaffold presets — defer: driven by the first app that needs them

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Push→build→deploy pipeline | HIGH | MEDIUM | P1 |
| GitOps engine (auto-sync/self-heal/prune) | HIGH | LOW | P1 |
| Wildcard DNS/proxy/TLS rail | HIGH | LOW–MEDIUM | P1 |
| Secrets management | HIGH | MEDIUM | P1 |
| Scaffold CLI v1 | HIGH | MEDIUM | P1 |
| Postgres LXC + app connectivity | HIGH | LOW | P1 |
| Opt-in public exposure | MEDIUM | MEDIUM | P1 (required, minimal form) |
| Per-app DB provisioning | HIGH | MEDIUM | P2 |
| Deployment notifications | MEDIUM | LOW | P2 |
| Homepage auto-discovery | MEDIUM | LOW | P2 |
| App decommissioning | MEDIUM | LOW | P2 |
| Renovate | MEDIUM | LOW | P2 |
| Zitadel OIDC auto-provisioning | MEDIUM | HIGH | P3 |
| Staging overlays / promotion | LOW | MEDIUM | P3 |
| Preview environments | LOW | HIGH | P3 |

## Competitor Feature Analysis

| Feature | Coolify/Dokploy (self-hosted PaaS) | Reference k3s GitOps homelabs | Our Approach |
|---------|-------------------------------------|-------------------------------|--------------|
| App onboarding | Web UI wizard, imperative | Copy folder into repo / hand-write Application | Scaffold CLI → GitOps repo folder; ApplicationSet auto-registers |
| DNS/TLS | Built-in Traefik + Let's Encrypt per app | ExternalDNS + cert-manager annotations | Wildcard DNS/cert through existing NPM+Mikrotik; Ingress Host routing |
| Deploy trigger | Webhook / UI button | Git push + auto-sync | Git push only (GitOps as sole interface) |
| Database per app | One-click DB containers on same host | CloudNativePG in-cluster | External-Postgres operator against shared LXC — state stays outside cluster |
| Secrets | UI-stored env vars (opaque, not in git) | SOPS / Sealed Secrets / ESO | SOPS or ESO (rebuild-safe) |
| Visibility | Built-in dashboard | ArgoCD UI + gethomepage | Same: ArgoCD UI + gethomepage annotations |
| Rollback | UI redeploy of previous image | git revert | git revert + documented flow (no extra machinery) |

## Sources

- [cterence/homelab-gitops](https://github.com/cterence/homelab-gitops), [loeken/homelab](https://github.com/loeken/homelab), [pablodelarco/kubernetes-homelab](https://github.com/pablodelarco/kubernetes-homelab), [adavarski/homelab](https://github.com/adavarski/homelab) — reference feature sets (MEDIUM confidence, cross-checked)
- [Argo CD docs: Automated Sync Policy](https://argo-cd.readthedocs.io/en/latest/user-guide/auto_sync/), [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/), [Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) (MEDIUM — official docs via search)
- [Securing Local Kubernetes Apps with cert-manager, ExternalDNS, Cloudflare (ITNEXT)](https://itnext.io/securing-local-kubernetes-apps-a-practical-guide-with-cert-manager-externaldns-and-cloudflare-d1ee9342ed83); [Komodor: ExternalDNS + cert-manager](https://komodor.com/blog/simplifying-dns-automation-with-externaldns-and-cert-manager/) (MEDIUM)
- Secrets comparisons: [Stack Harbor](https://stackharbor.com/en/knowledge-base/gitops-secrets-sealed-sops-external/), [Jonas Hietala: SOPS+age and Sealed Secrets](https://www.jonashietala.se/blog/2026/05/31/sops_age_and_sealed_secrets/), [codedge: SOPS in homelab](https://www.codedge.de/posts/managing-secrets-sops-homelab/) (MEDIUM)
- [movetokube/postgres-operator (external Postgres)](https://github.com/movetokube/postgres-operator); [CloudNativePG](https://cloudnative-pg.io/) (MEDIUM)
- [gethomepage Kubernetes service discovery](https://gethomepage.dev/configs/kubernetes/) (MEDIUM — official docs)
- Environment modeling/promotion: [Codefresh: How to Model GitOps Environments](https://codefresh.io/blog/how-to-model-your-gitops-environments-and-promote-releases-between-them/), [Octopus GitOps environments guide](https://octopus.com/devops/gitops/gitops-environments/), [Loft/vcluster preview envs](https://www.loft.sh/blog/implementing-preview-environments-with-gitops-in-kubernetes) (MEDIUM)
- Backup norms: [picluster Velero docs](https://picluster.ricsanfre.com/docs/backup/), [k3s backup without complexity (dev.to)](https://dev.to/dwoitzik/k3s-backup-without-the-complexity-velero-garage-s3-on-longhorn-21de) (MEDIUM)
- Over-engineering retrospectives: [Gabor's Lab Notes: k3s homelab lessons](https://www.gaborl.hu/blog/kubernetes-in-a-homelab-lessons-from-my-k3s-cluster/), [Fernando Cejas: over-engineered homelab](https://fernandocejas.com/blog/engineering/2023-01-06-over-engineered-home-lab-docker-kubernetes/) (LOW — anecdotal, but consistent across sources)
- Notifications: [argocd-notifications](https://github.com/argoproj-labs/argocd-notifications), [ntfy homelab setup](https://blog.alexsguardian.net/posts/2023/09/12/selfhosting-ntfy) (MEDIUM)
- Image automation: [Flux Image Automation vs ArgoCD Image Updater](https://oneuptime.com/blog/post/2026-03-13-flux-image-automation-vs-argocd-image-updater/view) (MEDIUM)

---
*Feature research for: GitOps homelab deployment platform*
*Researched: 2026-07-07*
