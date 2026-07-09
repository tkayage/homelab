#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/infrastructure/edge/public-edge.json"
LOCAL_CONTRACT="$ROOT/infrastructure/edge/local-edge.json"
CF_ENV="${CF_ENV:-/home/tonny/.config/homelab/cloudflare.env}"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
OWNER="$(jq -r .owner "$CONTRACT")"
ZONE="$(jq -r .dns.zone "$CONTRACT")"
SUFFIX="$(jq -r .dns.suffix "$CONTRACT")"
WILDCARD="$(jq -r .dns.wildcard "$CONTRACT")"
TARGET="$(jq -r .dns.public_target "$CONTRACT")"
PROOF_HOST="$(jq -r .proof.hostname "$CONTRACT")"
PROOF_PATH="$(jq -r .proof.health_path "$CONTRACT")"
export KUBECONFIG

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }

load_credentials() {
  [[ -r "$CF_ENV" ]] || die "missing credentials: $CF_ENV"
  set -a
  # shellcheck disable=SC1090
  source "$CF_ENV"
  set +a
  [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || die "incomplete Cloudflare credentials"
}

cf() {
  local method="$1" path="$2" body="${3:-}" out status
  out="$(mktemp "$ROOT/.local/cf-response.XXXXXX")"
  chmod 600 "$out"
  if [[ -n "$body" ]]; then
    status="$(curl -fsS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H 'Content-Type: application/json' \
      -d "$body" "https://api.cloudflare.com/client/v4$path" || true)"
  else
    status="$(curl -fsS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4$path" || true)"
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    local message
    message="$(jq -r '.errors[0].message // .message // "request failed"' "$out" 2>/dev/null || printf 'request failed')"
    rm -f "$out"
    die "Cloudflare $method $path failed ($status): $message"
  fi
  cat "$out"
  rm -f "$out"
}

zone_id() {
  cf GET "/zones?name=$ZONE" | jq -r '.result[0].id // empty'
}

preflight() {
  for command in curl jq dig kubectl; do need "$command"; done
  jq -e '.owner == "homelab-platform-public-edge" and .dns.wildcard == "*.app.kayage.co" and (.denylist | length >= 6)' "$CONTRACT" >/dev/null
  jq -e '.dns.wildcard == "*.app.kayage.co" and .proxy.forward_host == "10.10.30.102"' "$LOCAL_CONTRACT" >/dev/null
  load_credentials
  cf GET '/user/tokens/verify' | jq -e '.success and .result.status == "active"' >/dev/null
  printf 'public edge preflight passed\n'
}

assert_no_public_wildcard() {
  local zid count
  load_credentials
  zid="$(zone_id)"
  [[ -n "$zid" ]] || die "Cloudflare zone $ZONE unavailable"
  count="$(cf GET "/zones/$zid/dns_records?type=A&name=$WILDCARD" | jq '.result | length')"
  [[ "$count" == 0 ]] || die "public wildcard DNS record exists for $WILDCARD"
}

record_name() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid slug: $slug"
  printf '%s.%s\n' "$slug" "$SUFFIX"
}

record_id() {
  local name="$1" zid="$2"
  cf GET "/zones/$zid/dns_records?type=CNAME&name=$name" |
    jq -r --arg owner "$OWNER" '.result[] | select((.comment // "") == $owner) | .id' | head -1
}

prove_enable() {
  local slug="${1:-}" name zid rid body
  [[ -n "$slug" ]] || die "usage: $0 prove-enable <slug>"
  preflight >/dev/null
  assert_no_public_wildcard
  name="$(record_name "$slug")"
  zid="$(zone_id)"
  rid="$(record_id "$name" "$zid")"
  body="$(jq -n --arg type CNAME --arg name "$name" --arg content "$TARGET" --arg comment "$OWNER" \
    '{type:$type,name:$name,content:$content,ttl:300,proxied:false,comment:$comment}')"
  if [[ -n "$rid" ]]; then
    cf PUT "/zones/$zid/dns_records/$rid" "$body" >/dev/null
  else
    cf POST "/zones/$zid/dns_records" "$body" >/dev/null
  fi
  printf 'public record enabled: %s -> %s\n' "$name" "$TARGET"
}

prove_disable() {
  local slug="${1:-}" name zid rid
  [[ -n "$slug" ]] || die "usage: $0 prove-disable <slug>"
  load_credentials
  name="$(record_name "$slug")"
  zid="$(zone_id)"
  rid="$(record_id "$name" "$zid")"
  if [[ -n "$rid" ]]; then
    cf DELETE "/zones/$zid/dns_records/$rid" >/dev/null
  fi
  printf 'public record disabled: %s\n' "$name"
}

assert_default_deny() {
  local slug="${1:-edge-smoke}" name zid count
  preflight >/dev/null
  assert_no_public_wildcard
  name="$(record_name "$slug")"
  zid="$(zone_id)"
  count="$(cf GET "/zones/$zid/dns_records?name=$name" | jq '.result | length')"
  [[ "$count" == 0 ]] || die "unexpected public DNS record exists for default-deny app $name"
  printf 'default-deny passed for %s\n' "$name"
}

status() {
  local zid
  load_credentials
  zid="$(zone_id)"
  [[ -n "$zid" ]] || die "Cloudflare zone $ZONE unavailable"
  printf 'public edge records managed by %s:\n' "$OWNER"
  cf GET "/zones/$zid/dns_records?per_page=100&type=CNAME" |
    jq -r --arg owner "$OWNER" '.result[] | select((.comment // "") == $owner) | "  \(.name) -> \(.content)"'
}

scan_admin() {
  local failures=0
  while IFS=$'\t' read -r name host ports; do
    IFS=',' read -ra port_list <<<"$ports"
    for port in "${port_list[@]}"; do
      if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        printf 'admin surface exposed: %s %s:%s\n' "$name" "$host" "$port" >&2
        failures=$((failures + 1))
      fi
    done
  done < <(jq -r '.denylist[] | [.name, .host, (.ports | join(","))] | @tsv' "$CONTRACT")
  [[ "$failures" -eq 0 ]] || die "$failures admin surface checks failed"
  printf 'admin surface scan passed\n'
}

prove_reachability() {
  local ip
  ip="$(dig +short "$PROOF_HOST" A | tail -1)"
  [[ -n "$ip" ]] || die "no public DNS answer for $PROOF_HOST"
  curl -fsS "https://$PROOF_HOST$PROOF_PATH" >/dev/null
  printf 'public reachability passed: %s (%s)\n' "$PROOF_HOST" "$ip"
}

case "${1:-}" in
  preflight) preflight ;;
  assert-default-deny) assert_default_deny "${2:-edge-smoke}" ;;
  status) status ;;
  prove-enable) prove_enable "${2:-}" ;;
  prove-disable) prove_disable "${2:-}" ;;
  scan-admin) scan_admin ;;
  prove-reachability) prove_reachability ;;
  *) die "usage: $0 {preflight|assert-default-deny [slug]|status|prove-enable <slug>|prove-disable <slug>|scan-admin|prove-reachability}" ;;
esac
