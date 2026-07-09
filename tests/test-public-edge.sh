#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/infrastructure/edge/public-edge.json"
SCRIPT="$ROOT/scripts/public-edge.sh"
INGRESS="$ROOT/scaffold/internal/templates/files/gitops/ingress.yaml.tmpl"
pass=0

check() { "$@" >/dev/null; pass=$((pass + 1)); }
contains() { rg -q "$1" "$2"; }
contains_fixed() { rg -Fq "$1" "$2"; }
not_contains() { ! rg -q "$1" "$2"; }

static_tests() {
  check bash -n "$SCRIPT"
  check jq -e '.owner == "homelab-platform-public-edge" and .dns.wildcard == "*.app.kayage.co" and .dns.public_target == "public-edge.kayage.co" and (.denylist | length >= 6)' "$CONTRACT"
  check contains 'assert_no_public_wildcard' "$SCRIPT"
  check contains 'type=CNAME' "$SCRIPT"
  check contains 'comment.*OWNER' "$SCRIPT"
  check contains 'scan_admin' "$SCRIPT"
  check contains_fixed 'homelab.kayage.co/public: "{{if .Public}}true{{else}}false{{end}}"' "$INGRESS"
  check contains_fixed 'external-dns.alpha.kubernetes.io/hostname: {{.Slug}}.app.kayage.co' "$INGRESS"
  check contains 'external-dns.alpha.kubernetes.io/target: public-edge.kayage.co' "$INGRESS"
  check not_contains 'external-dns.alpha.kubernetes.io/hostname: \\*\\.app\\.kayage\\.co' "$INGRESS"
  check not_contains 'POST.*/dns_records.*\\*\\.app\\.kayage\\.co' "$SCRIPT"
  for surface in proxmox argocd npm-admin traefik-dashboard mikrotik postgres services; do
    check jq -e --arg surface "$surface" '.denylist[] | select(.name == $surface)' "$CONTRACT"
  done
  if rg -n 'CLOUDFLARE_API_TOKEN=.*[A-Za-z0-9_-]{20}|ghp_|AGE-SECRET-KEY-|password[[:space:]]*=' "$ROOT/infrastructure/edge/public-edge.json" "$SCRIPT"; then
    printf 'credential signature found\n' >&2
    exit 1
  fi
  pass=$((pass + 1))
}

case "${1:-}" in
  static) static_tests ;;
  *) printf 'usage: %s {static}\n' "$0" >&2; exit 1 ;;
esac

printf '%d public-edge checks passed\n' "$pass"
