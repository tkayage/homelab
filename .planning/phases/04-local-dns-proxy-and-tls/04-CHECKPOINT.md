---
phase: 04-local-dns-proxy-and-tls
plan: 01
status: blocked
updated: 2026-07-07T18:01:00Z
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

## Required operator action

Grant the token in `/home/tonny/.config/homelab/cloudflare.env` **Zone → DNS → Edit** and **Zone → Zone → Read**, restricted to `kayage.co`. Replace the token value in that file if a new token is created.

## Resume command

```bash
bash scripts/local-edge.sh apply
```

After apply succeeds, continue with `prove-zero-touch` and the live suite. No persistent RouterOS, NPM, or Cloudflare edge mutation occurred before this checkpoint.
