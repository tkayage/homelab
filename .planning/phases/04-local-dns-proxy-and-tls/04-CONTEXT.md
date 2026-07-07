---
phase: 04-local-dns-proxy-and-tls
status: discussed
date: 2026-07-07
---

# Phase 4 Context

## Phase boundary

Deliver zero-touch local exposure for applications through Mikrotik split DNS, existing Nginx Proxy Manager, and k3s Traefik with a valid Cloudflare DNS-01 wildcard certificate. Public Cloudflare records and AWS Mikrotik ingress remain Phase 7.

## Decisions

### Wildcard-first edge rail

- Create one LAN wildcard/regex DNS rule for `*.app.kayage.co` resolving to NPM at `10.10.30.237`.
- Create one NPM wildcard proxy host forwarding to k3s/Traefik at `10.10.30.102` while preserving the original Host header.
- Per-app Kubernetes Ingress resources provide host routing; adding/removing an app must not mutate Mikrotik, NPM, or certificates.
- Validate wildcard behavior end to end. Build per-app edge API automation only if the wildcard path cannot satisfy the acceptance tests.

### TLS ownership

- NPM owns the Cloudflare DNS-01 wildcard certificate for `*.app.kayage.co` and terminates client TLS.
- NPM forwards HTTP to Traefik over the trusted LAN; Kubernetes cert-manager is not introduced.
- The certificate must be issued without making application DNS public.

### Ownership and safety

- External configuration automation owns the one-time Mikrotik/NPM wildcard rail.
- Argo CD owns per-app Ingress resources inside k3s.
- In-cluster controllers must not receive router, NPM, or Cloudflare infrastructure credentials.
- Automation may manage only clearly labeled platform entries and must not expose administration surfaces.

## Acceptance behavior

- Use a committed smoke hostname under `app.kayage.co` and route it through Mikrotik → NPM → Traefik → workload.
- Verify valid certificate chain/hostname, Host routing, websocket upgrade, large request handling, and forwarded client headers.
- Prove application add/remove needs only a GitOps directory/manifest change after the wildcard rail exists.

## Deferred

- Public DNS and AWS Mikrotik routing remain Phase 7.
- General application scaffolding remains Phase 6.
- Administrative UIs remain local and are not automatically exposed.
