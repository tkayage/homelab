---
phase: 04-local-dns-proxy-and-tls
plan: 01
status: blocked
updated: 2026-07-07T17:43:00Z
---

# Phase 4 Permission Checkpoint

## Completed

- Wildcard edge contract, scoped reconciliation script, tests, and runbook implemented.
- `edge-smoke` published through GitOps and verified Synced/Healthy behind Traefik.
- Cloudflare token is active and can read the `kayage.co` zone; no public wildcard record exists.
- Static suite passes 7 checks.

## Blocking permissions

- RouterOS user `homelab` belongs to `read` and has explicit `!write`; creating the labeled static DNS regex returns `not enough permissions (9)`.
- NPM user `homelab` has `proxy_hosts=view` and `certificates=view`; valid create requests are hidden as 404 by NPM authorization.

## Required operator action

1. Grant the RouterOS `homelab` automation identity REST read/write access sufficient to manage `/ip/dns/static` (prefer a dedicated least-privilege group).
2. In NPM, change user `homelab` permissions for **Proxy Hosts** and **SSL Certificates** from View to Manage.
3. Keep the credential values in the existing `/home/tonny/.config/homelab/mikrotik.env` and `npm.env` files; no new secrets are needed if the same identities are elevated.

## Resume command

```bash
bash scripts/local-edge.sh apply
```

After apply succeeds, continue with `prove-zero-touch` and the live suite. No RouterOS or NPM mutation occurred before this checkpoint.
