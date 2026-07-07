#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/infrastructure/edge/local-edge.json"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
HOST="$(jq -r .smoke_hostname "$CONTRACT")"
NPM_IP="$(jq -r .dns.target_ipv4 "$CONTRACT")"
export KUBECONFIG
pass=0
check() { "$@" >/dev/null; pass=$((pass + 1)); }
contains() { rg -q "$1" "$2"; }

static_tests() {
  check bash -n "$ROOT/scripts/local-edge.sh"
  check jq -e '.owner == "homelab-platform-local-edge" and .dns.wildcard == "*.app.kayage.co" and .proxy.websockets and .proxy.max_body_mib >= 4' "$CONTRACT"
  check contains 'ingressClassName: traefik' "$ROOT/gitops/apps/edge-smoke/ingress.yaml"
  check contains 'edge-smoke.app.kayage.co' "$ROOT/gitops/apps/edge-smoke/ingress.yaml"
  check contains 'allow_websocket_upgrade:true' "$ROOT/scripts/local-edge.sh"
  check contains 'client_max_body_size 16m' "$ROOT/scripts/local-edge.sh"
  if rg -n 'dns_cloudflare_api_token[[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{20}|ghp_|AGE-SECRET-KEY-' "$ROOT/infrastructure/edge" "$ROOT/gitops/apps/edge-smoke" "$ROOT/docs/local-edge.md"; then
    printf 'credential signature found\n' >&2; exit 1
  fi
  pass=$((pass + 1))
}

live_tests() {
  [[ "$(dig +short @10.10.30.1 "$HOST" A | tail -1)" == "$NPM_IP" ]]
  pass=$((pass + 1))
  check kubectl -n edge-smoke rollout status deployment/edge-smoke --timeout=2m
  [[ "$(kubectl -n argocd get application edge-smoke -o jsonpath='{.status.sync.status}/{.status.health.status}')" == Synced/Healthy ]]
  pass=$((pass + 1))
  response="$(curl -fsS --resolve "$HOST:443:$NPM_IP" "https://$HOST/headers")"
  [[ "$(jq -r .hostname <<<"$response")" == "$HOST" ]]
  pass=$((pass + 1))
  [[ "$(jq -r '.headers["x-forwarded-proto"]' <<<"$response")" == https ]]
  pass=$((pass + 1))
  [[ "$(jq -r '.headers["x-forwarded-host"]' <<<"$response")" == "$HOST" ]]
  pass=$((pass + 1))
  cert="$(mktemp)"
  openssl s_client -connect "$NPM_IP:443" -servername "$HOST" -verify_return_error </dev/null 2>/dev/null | openssl x509 -outform PEM >"$cert"
  check openssl x509 -in "$cert" -noout -checkhost "$HOST"
  check openssl x509 -in "$cert" -noout -checkend $((21 * 86400))
  rm -f "$cert"
  headers="$(curl --http1.1 -sS -D - -o /dev/null --resolve "$HOST:443:$NPM_IP" \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "https://$HOST/ws" || true)"
  rg -q '^HTTP/1.1 101' <<<"$headers"
  pass=$((pass + 1))
  bytes=$((4 * 1024 * 1024))
  received="$(head -c "$bytes" /dev/zero | tr '\0' x | curl -fsS --resolve "$HOST:443:$NPM_IP" -H 'Content-Type: application/octet-stream' --data-binary @- "https://$HOST/upload" | jq -r .bodyBytes)"
  [[ "$received" == "$bytes" ]]
  pass=$((pass + 1))
  [[ -f "$ROOT/.local/phase-04-zero-touch-proof" ]]
  pass=$((pass + 1))
}

case "${1:-}" in
  static) static_tests ;;
  live) static_tests; live_tests ;;
  *) printf 'usage: %s {static|live}\n' "$0" >&2; exit 1 ;;
esac
printf '%d local-edge checks passed\n' "$pass"
