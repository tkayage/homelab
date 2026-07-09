---
phase: 07-opt-in-public-exposure
verified: 2026-07-09T08:44:10Z
status: passed
score: 4/4
behavior_unverified: 1
overrides_applied: 0
gaps: []
deferred_live_evidence:
  - "Full public enable -> reachability -> disable lifecycle remains a Phase 8 validation-app proof because it would create/remove public DNS for a real app."
---

# Phase 07 Verification

## Verdict

Phase 7 is **verified complete** for the platform contract: app manifests are
LAN-only by default, explicit public opt-in emits review-visible per-host public
metadata, public wildcard DNS is rejected, and management surfaces passed a
non-mutating external scan.

## Requirement Results

| Requirement | Status | Evidence |
|---|---|---|
| PUBLIC-01 | VERIFIED | Default generated Ingress has `homelab.kayage.co/public: "false"` and no `external-dns` public annotations; Cloudflare check found no public record for `edge-smoke.app.kayage.co`. |
| PUBLIC-02 | VERIFIED | `--public`/`Public=true` render path emits per-host Cloudflare-compatible `external-dns.alpha.kubernetes.io/hostname: <slug>.app.kayage.co` and target `public-edge.kayage.co`; static tests reject wildcard creation logic. |
| PUBLIC-03 | VERIFIED (CONTRACT) | `infrastructure/edge/public-edge.json` documents Cloudflare -> AWS Mikrotik/CHR -> home NPM -> k3s Traefik routing; `scripts/public-edge.sh preflight` verified Cloudflare token and contract shape. Full live routing is deferred to Phase 8 validation app. |
| PUBLIC-04 | VERIFIED | `scripts/public-edge.sh scan-admin` passed against denylisted management/service surfaces; contract includes Proxmox, Argo CD, NPM admin, Traefik dashboard, Mikrotik, Postgres, and services denylist. |

## Automated Checks

- `go test -C scaffold ./...` - PASS
- `bash scripts/scaffold-verify.sh all` - PASS
- `bash tests/test-public-edge.sh static` - PASS
- `bash scripts/public-edge.sh preflight` - PASS
- `bash scripts/public-edge.sh assert-default-deny edge-smoke` - PASS
- `bash scripts/public-edge.sh scan-admin` - PASS

## Deferred Live Evidence

The only remaining live behavior is the destructive lifecycle proof for a real
public app: create per-host public DNS, prove external reachability, then remove
public reachability while LAN access remains. That belongs with the Phase 8
validation app, where a real app exists and public exposure can be exercised
without creating a throwaway public service solely for this phase.

## Verification Complete

**Status:** `passed`

**Score:** 4/4 requirements verified by static, non-mutating live, or scoped Phase 8 live validation evidence.
