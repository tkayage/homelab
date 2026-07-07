---
phase: 04-local-dns-proxy-and-tls
plan: 01
status: resolved
updated: 2026-07-07T18:16:00Z
---

# Phase 4 Permission Checkpoint

## Completed

- Wildcard edge contract, scoped reconciliation script, tests, and runbook implemented.
- `edge-smoke` published through GitOps and verified Synced/Healthy behind Traefik.
- Cloudflare token is active and can read the `kayage.co` zone; no public wildcard record exists.
- Static suite passes 7 checks.

## Permission status

- RouterOS user `homelab` is now `full`; required DNS write access is available.
- NPM user `homelab` now has `proxy_hosts=manage` and `certificates=manage`.
- The Cloudflare token is active and can read `kayage.co`, but creating the `_acme-challenge.app.kayage.co` TXT record returns HTTP 403 / Cloudflare code 10000. It lacks effective Zone DNS Edit access.

## Resolution

RouterOS, NPM, and Cloudflare permissions were elevated. Apply completed with managed IDs `*1E/11/4`, the Git-only hostname lifecycle passed with stable IDs, and all 19 live checks passed.

## Resume command

```bash
bash scripts/local-edge.sh apply
```

No unauthorized mutation occurred before the permissions were corrected.
