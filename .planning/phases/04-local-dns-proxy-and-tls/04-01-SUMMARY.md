---
phase: 04-local-dns-proxy-and-tls
plan: 01
subsystem: edge
tags: [routeros, nginx-proxy-manager, traefik, letsencrypt, cloudflare]
requires:
  - phase: 03-gitops-and-secrets-bootstrap
    provides: Argo CD app discovery and encrypted GitOps repository
provides:
  - Wildcard split DNS from RouterOS to NPM
  - Valid Let's Encrypt wildcard TLS through Cloudflare DNS-01
  - NPM wildcard forwarding to Traefik with trusted forwarded headers
  - Zero-touch per-app hostname lifecycle through Kubernetes Ingress
affects: [phase-06, phase-07, phase-08]
tech-stack:
  added: [lego v5.2.2, RouterOS static DNS regex, NPM wildcard proxy]
  patterns: [wildcard-edge-rail, externalTrafficPolicy-local, scoped-forwarder-trust]
key-files:
  created: [infrastructure/edge/local-edge.json, scripts/local-edge.sh, tests/test-local-edge.sh, gitops/apps/edge-smoke/ingress.yaml, gitops/platform/traefik-forwarded-headers.yaml, docs/local-edge.md]
key-decisions:
  - "Use one wildcard DNS/proxy/certificate rail and keep per-app routing in GitOps Ingress resources."
  - "Issue with checksum-pinned lego and upload to NPM after NPM's internal ACME worker returned opaque 500 errors."
  - "Preserve source IP using externalTrafficPolicy Local and trust forwarded headers only from NPM's /32."
requirements-completed: [EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-05]
coverage:
  - {id: D1, description: Local wildcard DNS resolves to NPM, requirement: EDGE-01, verification: [{kind: integration, ref: "dig direct to RouterOS", status: pass}], human_judgment: false}
  - {id: D2, description: Trusted wildcard TLS terminates at NPM, requirement: EDGE-02, verification: [{kind: integration, ref: "OpenSSL chain hostname expiry", status: pass}], human_judgment: false}
  - {id: D3, description: NPM and Traefik route by Host, requirement: EDGE-03, verification: [{kind: integration, ref: "HTTPS echo routing", status: pass}], human_judgment: false}
  - {id: D4, description: Protocol and forwarding behavior, requirement: EDGE-04, verification: [{kind: integration, ref: "101 upgrade 4 MiB body forwarded headers", status: pass}], human_judgment: false}
  - {id: D5, description: Git-only hostname lifecycle, requirement: EDGE-05, verification: [{kind: integration, ref: "80656c1 reverted by 8b0dc51 with stable IDs", status: pass}], human_judgment: false}
duration: 45min
completed: 2026-07-07
status: complete
---

# Phase 4 Plan 1 Summary

Every `*.app.kayage.co` GitOps Ingress now receives automatic local DNS, trusted TLS, and Host routing through NPM and Traefik.

- Created RouterOS DNS ID `*1E`, NPM proxy ID `11`, and certificate ID `4`.
- Verified TLS, routing, websocket, 4 MiB requests, and forwarded headers.
- Proved Git-only hostname add/remove with stable external IDs.
- Re-ran apply idempotently and passed all 19 checks.

NPM's internal ACME worker returned an opaque HTTP 500, so checksum-pinned lego performs DNS-01 issuance and uploads the certificate to NPM. Traefik uses `externalTrafficPolicy: Local` to preserve source addresses and trusts only NPM's `/32`.
