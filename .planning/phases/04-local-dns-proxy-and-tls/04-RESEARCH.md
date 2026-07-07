---
phase: 04-local-dns-proxy-and-tls
date: 2026-07-07
status: complete
---

# Phase 4 Research

The live edge is RouterOS 7.23.1 at the authenticated REST endpoint and NPM at `10.10.30.237`. RouterOS has per-host static DNS entries but no existing `app.kayage.co` wildcard/regex rule. NPM has ten unrelated proxy hosts and one valid Let's Encrypt certificate for `*.kayage.co`, `*.hapa.dev`, and `*.kasia.tech`; that certificate does not cover names such as `edge-smoke.app.kayage.co` because TLS wildcards match only one label.

Use a labeled RouterOS static DNS regex `^.+\.app\.kayage\.co$` returning `10.10.30.237`. Use one NPM proxy host for `*.app.kayage.co`, forwarding HTTP to Traefik on `10.10.30.102:80`, forcing TLS, enabling HTTP/2 and websocket upgrades, and allowing a tested request size. Issue a dedicated Let's Encrypt certificate for `*.app.kayage.co` through NPM's Cloudflare DNS provider using the external zone-scoped token. Do not create a public application DNS record.

The GitOps smoke application should add an Ingress and a small protocol echo workload. Verification must query RouterOS DNS directly, validate the served certificate name/chain and expiry, prove Host routing, websocket upgrade, a multi-megabyte request, and forwarded headers, then add/remove a second GitOps hostname without changing the edge resource identities.

Primary references: RouterOS DNS static regex and REST API documentation; Nginx Proxy Manager certificate/proxy-host API schemas and source; Cloudflare zone-scoped API-token documentation; Kubernetes Ingress v1 documentation.
