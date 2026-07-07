# Stack Research

**Domain:** GitOps homelab deployment platform (k3s on Proxmox, automated per-app DNS/reverse-proxy/TLS)
**Researched:** 2026-07-07
**Confidence:** MEDIUM (recommendations cross-checked across multiple sources; all version numbers verified against GitHub Releases API on research date)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| k3s | v1.36.2+k3s1 | Kubernetes for app workloads (single VM) | Already decided in PROJECT.md; single-binary, batteries-included (Traefik, ServiceLB, local-path storage), ideal for a disposable single-node cluster |
| Argo CD | v3.4.4 | GitOps engine | Built-in web UI is the killer feature for a solo operator: live app map, health, diff, one-click rollback without kubectl. Webhook-triggered sync means deploys start seconds after push (Flux defaults to polling). ApplicationSet controller (bundled) auto-discovers new apps from a git directory — this IS the scaffolding registration mechanism |
| Traefik (k3s-bundled) | v3.7.4 (ships in k3s v1.36.2) | In-cluster ingress controller | Zero install/maintenance — k3s deploys and upgrades it. Behind NPM the ingress job is trivial (Host-header routing to Services); nothing ingress-nginx does better justifies ripping out the default. Customize via `HelmChartConfig` if needed |
| OpenTofu | v1.12.3 | IaC runner for Proxmox + edge wiring | Open-source Terraform fork, drop-in compatible with all providers below; avoids BUSL licensing questions for a long-lived personal platform |
| bpg/proxmox provider | v0.111.1 | Provision k3s VM + shared-service LXCs on Proxmox | The actively maintained Proxmox provider (weekly releases, Proxmox VE 9.x support). Handles VMs, LXC containers, cloud-init user-data via snippets, template cloning. The telmate provider is effectively abandoned |
| cloud-init | (bundled in Debian/Ubuntu cloud images) | First-boot config of the k3s VM | Standard pattern with bpg provider: clone a cloud image template, inject user-data snippet that installs k3s + registers node. Keeps the VM rebuildable from code |
| GitHub Actions + GHCR | actions/checkout@v5, docker/build-push-action@v7 | CI: build images, push to GHCR | Already decided (GHCR); `GITHUB_TOKEN` with `packages: write` means zero credential management for pushes from the same org/user |
| SOPS + age | SOPS v3.13.2 | Secrets in the GitOps repo | Secrets encrypted in git survive full cluster rebuild — critical because the k3s cluster is explicitly disposable. One age keypair, decryptable on any machine. Not cluster-bound (unlike sealed-secrets, whose sealing key lives in the cluster you plan to destroy) |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| external-dns | v0.21.0 | Auto-create DNS records from Ingress resources | Run **two instances**: one with the Mikrotik webhook (LAN, default for every app), one with the native Cloudflare provider (public, opt-in via annotation filter) |
| external-dns-provider-mikrotik (mirceanton) | v1.6.3 | external-dns webhook sidecar for RouterOS static DNS | The per-app Mikrotik static DNS entry requirement, fully GitOps-native: Ingress created → LAN record appears; app deleted → record cleaned up |
| Sander0542/nginxproxymanager (Tofu provider) | v1.3.0 | Declaratively manage NPM proxy hosts via NPM's REST API | No Kubernetes controller exists for NPM — this is the gap. Scaffolder runs `tofu apply` to create the per-app proxy host (domain → Traefik LB IP, websockets on) |
| cert-manager | v1.20.3 | In-cluster ACME certs via Cloudflare DNS-01 | **Optional for v1** — see TLS decision below. Add when you want end-to-end TLS (NPM → Traefik over HTTPS) instead of TLS terminating at NPM |
| Helm (as ArgoCD source type) | Helm 3.x (bundled in ArgoCD) | One shared "app chart" templating Deployment/Service/Ingress | All T3 apps are shape-identical; a single library chart + tiny per-app `values.yaml` beats N copies of Kustomize bases. ArgoCD renders it natively — no `helm install` ever runs |
| KSOPS (CMP sidecar) | latest ksops image | SOPS decryption inside ArgoCD | Required to make ArgoCD consume SOPS-encrypted secrets. This is ArgoCD's roughest edge (Flux has native SOPS) — budget setup time for the ConfigManagementPlugin sidecar |
| docker/metadata-action | v6.2.0 | Image tags/labels (git SHA + branch) | In every app CI workflow |
| docker/login-action | v4.4.0 | GHCR auth with GITHUB_TOKEN | In every app CI workflow |
| docker/setup-buildx-action | v4.2.0 | Buildx for cache mounts | In every app CI workflow; pair with `cache-from/to: type=gha,mode=max` |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Custom TS scaffolder CLI (own code) | Per-project one-shot wiring | Emits: Dockerfile + GH Actions workflow into the app repo; `apps/<name>/` (values.yaml + ArgoCD-discoverable config) into the GitOps repo; runs `tofu apply` for the NPM proxy host. User is a TS dev — a small Node CLI (e.g. commander + template files) fits better than cookiecutter/copier |
| Renovate | Auto-PR dependency/image bumps in the GitOps repo | Understands Helm values, ArgoCD, Dockerfiles, GH Actions pins. Add after v1 ships (LOW confidence — not deep-researched) |
| yq | CI-side image tag bump in GitOps repo | The deploy step: CI writes new image tag into `apps/<name>/values.yaml` and pushes — ArgoCD picks it up. Simpler and more debuggable than ArgoCD Image Updater |
| k9s / ArgoCD UI | Day-2 cluster inspection | ArgoCD UI covers most solo-operator needs |

## Key Decisions Resolved (the eight open questions)

### 1. GitOps engine → **Argo CD v3.4.4** (confidence: MEDIUM)

For a solo dev the UI is not a luxury — it replaces the missing teammate. Every comparison surveyed lands the same way: ArgoCD for visibility and single-pane management, Flux for fleet-scale footprint. At one cluster, Flux's advantages (lean controllers, modularity) don't apply, and its weaknesses for this workflow do (no UI, 5-min poll default, CLI-driven debugging). ArgoCD's ApplicationSet git-directory generator also directly implements "scaffold registers the app": drop a folder in `apps/`, an Application appears.

Trade-off accepted: Flux has native SOPS decryption; ArgoCD needs the KSOPS plugin (see secrets).

### 2. Proxmox IaC → **OpenTofu + bpg/proxmox v0.111.1**, cloud-init for guest bootstrap (confidence: MEDIUM)

bpg/proxmox is the only actively developed Proxmox provider and supports both `proxmox_virtual_environment_vm` and `proxmox_virtual_environment_container` (LXC), so one tool provisions the k3s VM **and** the shared-service LXCs. Cloud-init pattern: upload a Debian/Ubuntu cloud image once, clone per VM, pass user-data via `proxmox_virtual_environment_file` snippets (requires SSH access to the PVE node for snippet upload — known provider quirk).

- Pulumi: rejected — its Proxmox support is a bridge of this same provider with an extra language runtime on top; no gain for a solo operator.
- Ansible: not for provisioning, but a legitimate **complement** for configuring inside LXCs (installing native Postgres/Valkey/NATS binaries, since cloud-init support in LXC templates is limited). Verdict: Tofu creates the containers; a small Ansible playbook (or plain shell over SSH) configures services inside them. Don't force everything through one tool.

### 3. k3s ingress → **keep bundled Traefik v3.7.x** behind NPM (confidence: MEDIUM)

Behind NPM, the in-cluster ingress only does Host-header routing on the LAN — the simplest possible job. Keeping the k3s default means zero install, zero upgrade management (k3s handles it), and ServiceLB gives Traefik a stable LAN IP on the VM. Write apps against the standard `Ingress` resource (not Traefik CRDs) for portability. NPM proxy hosts forward `myapp.domain.com` → Traefik's IP with the Host header preserved (NPM does this by default) and websockets enabled.

Swapping in ingress-nginx requires `--disable traefik`, a manual install, and buys nothing here.

### 4. TLS → **certs at NPM: one wildcard Let's Encrypt cert via NPM's built-in Cloudflare DNS-01** (confidence: MEDIUM)

This is the opinionated call: **do not run cert-manager in v1.**

- NPM natively supports Let's Encrypt DNS-01 with a Cloudflare API token. Request `*.yourdomain.com` once; every scaffolded proxy host references the same wildcard cert. Per-app TLS becomes free.
- NPM → Traefik traffic stays HTTP on the trusted LAN. Browsers see valid TLS end-to-end from their perspective.
- cert-manager in-cluster would force either double termination or making NPM a dumb TCP passthrough (which destroys NPM's per-app proxy-host model, a stated requirement).

Add cert-manager v1.20.3 later **only if** you want encrypted NPM→cluster hops. If you do: set `dns01RecursiveNameservers: "1.1.1.1:53,1.0.0.1:53"` or DNS-01 self-checks will fail behind your split-horizon Mikrotik DNS (the cluster would otherwise resolve the TXT record against LAN DNS).

### 5. Per-app DNS + proxy automation (confidence: MEDIUM)

Three surfaces, three answers:

| Surface | Tool | Trigger |
|---------|------|---------|
| Mikrotik LAN static DNS (default, every app) | external-dns v0.21.0 + mirceanton webhook v1.6.3 | Automatic from the app's Ingress resource — GitOps-native, cleans up on delete |
| Cloudflare public record (opt-in) | second external-dns instance, native Cloudflare provider, annotation-gated (e.g. only Ingresses labeled `expose: public`), records pointed at the AWS CHR public IP via `external-dns.alpha.kubernetes.io/target` | Automatic when the scaffolder/values flag flips public exposure on |
| NPM proxy host | OpenTofu + Sander0542/nginxproxymanager v1.3.0, state in the platform repo | Scaffold-time `tofu apply` (no k8s controller for NPM exists) |

Simplification worth considering during roadmap: a single **wildcard** NPM proxy host (`*.yourdomain.com` → Traefik) plus a wildcard Mikrotik static entry would eliminate two of the three per-app steps entirely — Traefik's Ingress rules already disambiguate hosts. Per-app entries give per-app control (and match the stated requirement); the wildcard gives less machinery. Decide in roadmap, not here.

### 6. CI → GitHub Actions → GHCR (confidence: MEDIUM, versions verified)

Standard per-app workflow (scaffolder emits it):

1. `actions/checkout@v5`
2. `docker/setup-buildx-action@v4`
3. `docker/login-action@v4` — `registry: ghcr.io`, `password: ${{ secrets.GITHUB_TOKEN }}` (needs `permissions: packages: write`)
4. `docker/metadata-action@v6` — tags: `sha` + branch
5. `docker/build-push-action@v7` — `cache-from/to: type=gha,mode=max`
6. Deploy step: `yq` bumps the image tag in the GitOps repo's `apps/<name>/values.yaml` and pushes (needs a fine-grained PAT or GitHub App token with write access to the GitOps repo)

Dockerfile: Next.js `output: "standalone"` multi-stage — deps → build → runner copying `.next/standalone` + `.next/static` + `public`, `CMD ["node", "server.js"]`. Works for any T3 app; non-Node apps just bring their own Dockerfile.

Note: docker/build-push-action is on **v7** and login-action on **v4** as of mid-2026 — most tutorials still show v6/v3; use the current majors.

### 7. Secrets → **SOPS v3.13.2 + age, KSOPS plugin in ArgoCD** (confidence: MEDIUM)

The deciding constraint is PROJECT.md's "cluster stays disposable." sealed-secrets binds decryption to a controller key **inside the cluster** — a rebuild without a key backup bricks every secret in git. SOPS+age keeps one private key on the dev server (plus offline backup); the GitOps repo is self-contained and re-appliable to a fresh cluster with zero ceremony. ESO is rejected for v1: it syncs from an external secret manager you don't run (Vault/cloud), so it's a solution to a problem this homelab doesn't have yet.

Honest cost: ArgoCD's SOPS story is a bolt-on (KSOPS CMP sidecar + age key mounted as a cluster secret). This is the one place Flux is genuinely smoother. Budget a focused setup session; it's a one-time cost.

### 8. Scaffolding shape → **one shared Helm app-chart + per-app values.yaml + ApplicationSet, emitted by a custom TS CLI** (confidence: MEDIUM)

- **Templating layer:** a single generic "web-app" Helm chart (Deployment, Service, Ingress, optional external-dns annotations, env-from-secret) lives once in the GitOps repo. Each app contributes only `apps/<name>/values.yaml` (~15 lines: image, host, port, env, `public: true/false`). This is the standard pattern for fleets of shape-identical apps; Kustomize base+overlay was rejected because every new app would copy a base and N patch files — more per-app surface, no gain when apps genuinely share one shape.
- **Registration layer:** ArgoCD ApplicationSet with a git-directory generator over `apps/*` — adding the folder IS the registration; no ArgoCD config edit per app.
- **CLI layer:** the scaffolder doesn't template Kubernetes YAML at all. It (a) drops Dockerfile + workflow into the app repo, (b) writes `apps/<name>/values.yaml` to the GitOps repo, (c) applies the NPM Tofu module. Build it in TypeScript — it's ~200 lines of file templating plus a git commit, in the language the user lives in.

## Installation

```bash
# --- Control machine (dev server) ---
# OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method deb   # v1.12.x
# SOPS + age
sudo apt install age
curl -LO https://github.com/getsops/sops/releases/download/v3.13.2/sops-v3.13.2.linux.amd64 && sudo install sops-* /usr/local/bin/sops
age-keygen -o ~/.config/sops/age/keys.txt
# ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/v3.4.4/argocd-linux-amd64 && sudo install argocd /usr/local/bin/

# --- Cluster (after Tofu provisions the VM; k3s via cloud-init) ---
# k3s pinned: INSTALL_K3S_VERSION=v1.36.2+k3s1 (keep bundled Traefik; no --disable flags needed)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.4/manifests/install.yaml
# Then: ArgoCD app-of-apps bootstraps external-dns (x2), KSOPS config, and the apps ApplicationSet
```

```hcl
# --- GitOps/platform repo: providers ---
terraform {
  required_providers {
    proxmox           = { source = "bpg/proxmox",                  version = "~> 0.111" }
    nginxproxymanager = { source = "Sander0542/nginxproxymanager", version = "~> 1.3" }
  }
}
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Argo CD | Flux v2.9.0 | You'll never look at a UI, want native SOPS decryption, or later run many clusters where controller footprint multiplies |
| OpenTofu + bpg/proxmox | Ansible-only provisioning | You already have a large Ansible estate and refuse HCL; loses plan/diff/state for infra |
| Bundled Traefik | ingress-nginx | You need nginx-specific annotations/snippets or hit a Traefik-specific bug; requires `--disable traefik` on k3s |
| Wildcard cert at NPM | cert-manager v1.20.3 in-cluster (Cloudflare DNS-01) | You want end-to-end TLS NPM→Traefik, or per-app (non-wildcard) certs for hostname-privacy in CT logs |
| SOPS + age | sealed-secrets | You'd rather run a controller than configure KSOPS — but you MUST back up the sealing key or cluster rebuild loses everything |
| SOPS + age | external-secrets-operator | Only once a real secret manager (Vault, Infisical, cloud) enters the homelab |
| CI bumps values.yaml via yq | ArgoCD Image Updater | You want tag-tracking without CI writing to the GitOps repo; note the project has had maintenance gaps (LOW confidence — not verified this cycle) |
| Custom TS scaffolder CLI | copier/cookiecutter | If the CLI never needs to call APIs (NPM/git) — but it does, so a real program wins |
| external-dns Mikrotik webhook (mirceanton) | terraform-routeros provider at scaffold time | If you prefer all edge wiring in one Tofu apply over in-cluster reconciliation (UNVERIFIED provider status — check before adopting) |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| telmate/proxmox Terraform provider | Effectively unmaintained; breaks against Proxmox VE 8/9 APIs; most old tutorials reference it | bpg/proxmox v0.111.x |
| Flux for this project | 5-min poll default, no UI, CLI-only debugging — every "solo homelab" advantage lists point to ArgoCD | Argo CD v3.4.4 |
| sealed-secrets on a disposable cluster | Sealing key lives in-cluster; rebuild without key backup = all git-stored secrets unrecoverable | SOPS + age (key on dev server + offline backup) |
| ArgoCD Image Updater (v1) | Extra controller, historical maintenance concerns; CI-side tag bump is simpler to reason about | `yq` bump + push in the app's CI workflow |
| Traefik CRDs (IngressRoute) for apps | Locks the shared app-chart to Traefik; standard Ingress does everything this platform needs | `networking.k8s.io/v1` Ingress |
| Docker-in-LXC for shared services | Already excluded in PROJECT.md — nesting/apparmor breakage on Proxmox upgrades | Native binaries via Tofu-created LXC + Ansible/shell config |
| saffronjam/nginx-proxy-manager provider | Stale (last release 2022) | Sander0542/nginxproxymanager v1.3.0 |
| NPM as TCP passthrough to Traefik | Destroys per-app proxy-host model and NPM's value; two SNI routers fighting | Terminate TLS at NPM, HTTP to Traefik on LAN |
| Per-app Helm charts or Kustomize copies | N× duplicated manifests to keep in sync | One shared app-chart + per-app values.yaml |

## Stack Patterns by Variant

**Default app (local-only):**
- values.yaml: `host: myapp.domain.com`, `public: false`
- external-dns (Mikrotik instance) creates the LAN static entry → NPM IP
- Scaffolder's Tofu run created the NPM proxy host → Traefik, wildcard cert attached

**Opt-in public app:**
- values.yaml flips `public: true` → chart adds the Cloudflare external-dns annotation + `target:` pointing at the AWS CHR public IP
- Traffic: Cloudflare DNS → CHR → forward to NPM → Traefik (same LAN path after the edge)

**Non-T3 / arbitrary container:**
- Skip the emitted Dockerfile; anything that exposes an HTTP port uses the same chart (image + port in values)

**Shared-service LXCs (Postgres, Valkey, Debezium, NATS+JetStream):**
- Tofu `proxmox_virtual_environment_container` per service; configure with Ansible/shell; apps reach them via LAN DNS names (also Mikrotik static entries) — never through k8s Services

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| bpg/proxmox v0.111.x | OpenTofu ≥ 1.6 (some features need ≥ 1.10); Proxmox VE 9.x | Snippet upload for cloud-init user-data needs SSH access to the PVE node configured in the provider block |
| k3s v1.36.2+k3s1 | Kubernetes v1.36.2, Traefik v3.7.4, containerd 2.3.2 | ArgoCD v3.4 and cert-manager v1.20 both support k8s 1.36 |
| external-dns v0.21.0 | mirceanton webhook v1.6.3 (sidecar on localhost:8888) | v0.21.0 had breaking changes to several providers — pin the webhook image and read its compat notes on upgrade |
| ArgoCD v3.4.4 | Helm 3 sources, ApplicationSet bundled, KSOPS via CMP sidecar | KSOPS needs the age key mounted as a Secret in the argocd namespace |
| docker/build-push-action v7 | setup-buildx v4, login v4, metadata v6 | These majors moved together in 2026; older tutorial pins (v6/v3/v5) still work but lag |

## Sources

- GitHub Releases API (fetched 2026-07-07) — version verification for k3s, ArgoCD, Flux, cert-manager, external-dns, bpg/proxmox, OpenTofu, SOPS, mirceanton webhook, Sander0542 NPM provider, docker/* actions — MEDIUM (official source, single fetch each)
- [Northflank: Flux vs Argo CD](https://northflank.com/blog/flux-vs-argo-cd), [Portainer ArgoCD vs Flux guide](https://www.portainer.io/blog/argocd-vs-flux), [dev.to GitOps standard comparison](https://dev.to/mechcloud_academy/the-gitops-standard-in-2026-a-comparative-research-analysis-of-argocd-and-fluxcd-46d8) — GitOps engine choice — MEDIUM (multiple sources converge)
- [bpg/terraform-provider-proxmox](https://github.com/bpg/terraform-provider-proxmox) + [cloud-init guide](https://library.tf/providers/bpg/proxmox/latest/docs/guides/cloud-init) — provider capabilities, cloud-init pattern — MEDIUM
- [cert-manager Cloudflare DNS-01 docs](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/) — DNS-01 setup, recursive nameservers for split DNS — MEDIUM
- [external-dns Cloudflare tutorial](https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/cloudflare/), [mirceanton/external-dns-provider-mikrotik](https://github.com/mirceanton/external-dns-provider-mikrotik), [benfiola/external-dns-routeros-provider](https://github.com/benfiola/external-dns-routeros-provider) — DNS automation — MEDIUM
- [Sander0542/nginxproxymanager Terraform provider](https://registry.terraform.io/providers/Sander0542/nginxproxymanager/latest/docs) — NPM automation — MEDIUM
- [Docker docs: Next.js GitHub Actions](https://docs.docker.com/guides/nextjs/configure-github-actions/), [DEPT: speeding up Docker builds in GHA](https://engineering.deptagency.com/how-to-speed-up-docker-builds-in-github-actions) — CI patterns — MEDIUM
- [ArgoCD secret management docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/), [Jonas Hietala: SOPS+age and Sealed Secrets](https://www.jonashietala.se/blog/2026/05/31/sops_age_and_sealed_secrets/), [sanj.dev secrets comparison](https://sanj.dev/post/kubernetes-secrets-management-comparison/) — secrets choice — MEDIUM
- [Flux repo-structure guide](https://fluxcd.io/flux/guides/repository-structure/), [cloudogu/gitops-patterns](https://github.com/cloudogu/gitops-patterns), [ArgoCD Kustomize docs](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/) — scaffolding/repo shape — MEDIUM
- Traefik-vs-nginx comparisons ([Cast AI](https://cast.ai/blog/traefik-vs-nginx/), [vcluster](https://www.vcluster.com/blog/nginx-vs-traefik-vs-haproxy-comparing-kubernetes-ingress-controllers)) — ingress choice — MEDIUM
- UNVERIFIED items flagged inline: Renovate specifics, ArgoCD Image Updater current status, terraform-routeros provider health — LOW

---
*Stack research for: GitOps homelab deployment platform*
*Researched: 2026-07-07*
