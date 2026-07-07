#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/infrastructure/edge/local-edge.json"
MIKROTIK_ENV="${MIKROTIK_ENV:-/home/tonny/.config/homelab/mikrotik.env}"
NPM_ENV="${NPM_ENV:-/home/tonny/.config/homelab/npm.env}"
CF_ENV="${CF_ENV:-/home/tonny/.config/homelab/cloudflare.env}"
GH_ENV="${GH_ENV:-/home/tonny/.config/homelab/github.env}"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
OWNER="$(jq -r .owner "$CONTRACT")"
export KUBECONFIG

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }

load_credentials() {
  for file in "$MIKROTIK_ENV" "$NPM_ENV" "$CF_ENV"; do [[ -r "$file" ]] || die "missing credentials: $file"; done
  set -a
  # shellcheck disable=SC1090
  source "$MIKROTIK_ENV"
  source "$NPM_ENV"
  source "$CF_ENV"
  set +a
  [[ -n "${MIKROTIK_PASSWORD:-}" && -n "${NPM_PASSWORD:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" ]] || die "incomplete edge credentials"
  MT_CURL=(-fsS --max-time 60 --user "$MIKROTIK_USERNAME:$MIKROTIK_PASSWORD")
  NPM_CURL=(-sS --max-time 600)
  [[ "${MIKROTIK_VERIFY_TLS:-true}" == true ]] || MT_CURL+=(-k)
  [[ "${NPM_VERIFY_TLS:-true}" == true ]] || NPM_CURL+=(-k)
}

npm_login() {
  NPM_TOKEN="$(curl "${NPM_CURL[@]}" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg i "$NPM_USERNAME" --arg s "$NPM_PASSWORD" '{identity:$i,secret:$s}')" \
    "$NPM_URL/tokens" | jq -r .token)"
  [[ -n "$NPM_TOKEN" && "$NPM_TOKEN" != null ]] || die "NPM authentication failed"
}

npm_request() {
  local method="$1" path="$2" body="${3:-}" out status
  out="$(mktemp "$ROOT/.local/npm-response.XXXXXX")"
  chmod 600 "$out"
  if [[ -n "$body" ]]; then
    status="$(curl "${NPM_CURL[@]}" -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $NPM_TOKEN" -H 'Content-Type: application/json' -d "$body" "$NPM_URL$path" || true)"
  else
    status="$(curl "${NPM_CURL[@]}" -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $NPM_TOKEN" "$NPM_URL$path" || true)"
  fi
  if [[ ! "$status" =~ ^2 ]]; then
    message="$(jq -r '.error.message // .message // "request failed"' "$out" 2>/dev/null || printf 'request failed')"
    rm -f "$out"
    die "NPM $method $path failed ($status): $message"
  fi
  cat "$out"
  rm -f "$out"
}

preflight() {
  for command in curl jq kubectl git dig openssl docker ssh; do need "$command"; done
  jq -e '.dns.wildcard == "*.app.kayage.co" and .dns.target_ipv4 == "10.10.30.237" and .proxy.forward_host == "10.10.30.102"' "$CONTRACT" >/dev/null
  [[ -s "$KUBECONFIG" ]] || die "missing kubeconfig"
  load_credentials
  npm_login
  curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify | jq -e '.success and .result.status == "active"' >/dev/null
  kubectl get node >/dev/null
  printf 'edge preflight passed\n'
}

assert_no_public_record() {
  local zone_id count
  zone_id="$(curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    'https://api.cloudflare.com/client/v4/zones?name=kayage.co' | jq -r '.result[0].id // empty')"
  [[ -n "$zone_id" ]] || die "Cloudflare zone kayage.co unavailable"
  count="$(curl -fsS -G -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    --data-urlencode 'name=*.app.kayage.co' \
    "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" | jq '.result | length')"
  [[ "$count" == 0 ]] || die "public wildcard DNS record exists; local edge must remain private"
}

reconcile_dns() {
  local regexp address existing conflict payload
  regexp="$(jq -r .dns.routeros_regexp "$CONTRACT")"
  address="$(jq -r .dns.target_ipv4 "$CONTRACT")"
  existing="$(curl "${MT_CURL[@]}" "$MIKROTIK_URL/ip/dns/static" | jq -r --arg o "$OWNER" '.[] | select(.comment == $o) | .".id"')"
  conflict="$(curl "${MT_CURL[@]}" "$MIKROTIK_URL/ip/dns/static" | jq -r --arg r "$regexp" --arg o "$OWNER" '.[] | select(.regexp == $r and .comment != $o) | .".id"')"
  [[ -z "$conflict" ]] || die "unowned RouterOS wildcard conflict: $conflict"
  payload="$(jq -n --arg r "$regexp" --arg a "$address" --arg o "$OWNER" --arg ttl "$(jq -r .dns.ttl "$CONTRACT")" \
    '{regexp:$r,address:$a,type:"A",ttl:$ttl,comment:$o,disabled:"false"}')"
  if [[ -n "$existing" ]]; then
    curl "${MT_CURL[@]}" -X PATCH -H 'Content-Type: application/json' -d "$payload" "$MIKROTIK_URL/ip/dns/static/$existing" >/dev/null
    DNS_ID="$existing"
  else
    DNS_ID="$(curl "${MT_CURL[@]}" -X PUT -H 'Content-Type: application/json' -d "$payload" "$MIKROTIK_URL/ip/dns/static" | jq -r '.".id"')"
  fi
}

reconcile_certificate() {
  local certificates payload result archive lego data cert key issuer out status
  certificates="$(npm_request GET '/nginx/certificates')"
  CERT_ID="$(jq -r --arg n "$OWNER *.app.kayage.co" '.[] | select(.nice_name == $n and (.domain_names | index("*.app.kayage.co"))) | .id' <<<"$certificates" | head -1)"
  archive="$ROOT/.local/downloads/lego_v5.2.2_linux_amd64.tar.gz"
  lego="$ROOT/.local/bin/lego"
  if [[ ! -x "$lego" ]]; then
    mkdir -p "$ROOT/.local/downloads" "$ROOT/.local/bin"
    if [[ ! -s "$archive" ]]; then
      curl -fL --retry 5 -o "$archive" 'https://github.com/go-acme/lego/releases/download/v5.2.2/lego_v5.2.2_linux_amd64.tar.gz'
    fi
    echo "018de6d3f2da09630caa2fbbe8c6aa459323ad0ac0a053d0e808268914b38a8b  $archive" | sha256sum -c - >/dev/null
    tar -xOf "$archive" lego >"$lego"
    chmod 0755 "$lego"
  fi
  data="$ROOT/.local/lego"
  mkdir -p "$data"
  chmod 700 "$data"
  export CF_DNS_API_TOKEN="$CLOUDFLARE_API_TOKEN"
  "$lego" run --path "$data" --email "$NPM_USERNAME" --dns cloudflare \
    --dns.resolvers '1.1.1.1:53' --domains '*.app.kayage.co' --accept-tos >/dev/null
  cert="$data/certificates/_.app.kayage.co.crt"
  key="$data/certificates/_.app.kayage.co.key"
  issuer="$data/certificates/_.app.kayage.co.issuer.crt"
  [[ -s "$cert" && -s "$key" && -s "$issuer" ]] || die "lego did not produce the wildcard certificate files"
  if [[ -z "$CERT_ID" ]]; then
    payload="$(jq -n --arg owner "$OWNER" '{provider:"other",nice_name:($owner+" *.app.kayage.co"),domain_names:["*.app.kayage.co"],meta:{}}')"
    result="$(npm_request POST '/nginx/certificates' "$payload")"
    CERT_ID="$(jq -r .id <<<"$result")"
  fi
  out="$(mktemp "$ROOT/.local/npm-upload.XXXXXX")"; chmod 600 "$out"
  status="$(curl "${NPM_CURL[@]}" -o "$out" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $NPM_TOKEN" \
    -F "certificate=@$cert" -F "certificate_key=@$key" -F "intermediate_certificate=@$issuer" \
    "$NPM_URL/nginx/certificates/$CERT_ID/upload")"
  if [[ ! "$status" =~ ^2 ]]; then
    message="$(jq -r '.error.message // "certificate upload failed"' "$out" 2>/dev/null || true)"
    rm -f "$out"; die "NPM certificate upload failed ($status): $message"
  fi
  rm -f "$out"
  [[ "$CERT_ID" =~ ^[0-9]+$ ]] || die "NPM certificate reconciliation returned no id"
}

reconcile_proxy() {
  local hosts owned conflict payload result marker
  marker="# $OWNER"
  hosts="$(npm_request GET '/nginx/proxy-hosts')"
  owned="$(jq -r --arg w '*.app.kayage.co' --arg m "$marker" '.[] | select((.domain_names | index($w)) and (.advanced_config | contains($m))) | .id' <<<"$hosts")"
  conflict="$(jq -r --arg w '*.app.kayage.co' --arg m "$marker" '.[] | select((.domain_names | index($w)) and ((.advanced_config | contains($m)) | not)) | .id' <<<"$hosts")"
  [[ -z "$conflict" ]] || die "unowned NPM wildcard conflict: $conflict"
  payload="$(jq -n --argjson cert "$CERT_ID" --arg marker "$marker" '{domain_names:["*.app.kayage.co"],forward_scheme:"http",forward_host:"10.10.30.102",forward_port:80,certificate_id:$cert,ssl_forced:true,http2_support:true,block_exploits:true,caching_enabled:false,allow_websocket_upgrade:true,access_list_id:0,advanced_config:($marker+"\nclient_max_body_size 16m;"),enabled:true,locations:[],hsts_enabled:true,hsts_subdomains:false}')"
  if [[ -n "$owned" ]]; then
    result="$(npm_request PUT "/nginx/proxy-hosts/$owned" "$payload")"
  else
    result="$(npm_request POST '/nginx/proxy-hosts' "$payload")"
  fi
  PROXY_ID="$(jq -r .id <<<"$result")"
  [[ "$PROXY_ID" =~ ^[0-9]+$ ]] || die "NPM proxy reconciliation returned no id"
}

publish_smoke() {
  bash "$ROOT/scripts/gitops-platform.sh" publish >/dev/null
  for _ in $(seq 1 60); do
    if kubectl -n argocd get application edge-smoke >/dev/null 2>&1; then break; fi
    sleep 3
  done
  kubectl -n argocd annotate application edge-smoke argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  for _ in $(seq 1 60); do
    if kubectl -n edge-smoke get deployment edge-smoke >/dev/null 2>&1; then break; fi
    sleep 3
  done
  kubectl -n edge-smoke rollout status deployment/edge-smoke --timeout=10m
}

resource_ids() {
  local dns hosts certs
  dns="$(curl "${MT_CURL[@]}" "$MIKROTIK_URL/ip/dns/static" | jq -r --arg o "$OWNER" '.[] | select(.comment == $o) | .".id"')"
  hosts="$(npm_request GET '/nginx/proxy-hosts' | jq -r --arg m "# $OWNER" '.[] | select(.advanced_config | contains($m)) | .id')"
  certs="$(npm_request GET '/nginx/certificates' | jq -r --arg w '*.app.kayage.co' '.[] | select(.domain_names | index($w)) | .id' | head -1)"
  printf '%s/%s/%s\n' "$dns" "$hosts" "$certs"
}

status() {
  load_credentials; npm_login
  printf 'managed resource IDs (dns/proxy/certificate): %s\n' "$(resource_ids)"
  kubectl -n argocd get application edge-smoke
}

apply_edge() {
  preflight
  assert_no_public_record
  publish_smoke
  reconcile_certificate
  reconcile_proxy
  reconcile_dns
  printf 'managed resource IDs (dns/proxy/certificate): %s/%s/%s\n' "$DNS_ID" "$PROXY_ID" "$CERT_ID"
}

prove_zero_touch() {
  preflight
  local before after worktree="$ROOT/.local/gitops-homelab" commit host='edge-lifecycle.app.kayage.co'
  before="$(resource_ids)"
  set -a; source "$GH_ENV"; set +a
  export GIT_USERNAME=x-access-token GIT_PASSWORD="$GITHUB_TOKEN" GIT_ASKPASS="$ROOT/.local/git-askpass.sh" GIT_TERMINAL_PROMPT=0
  cat >"$worktree/apps/edge-smoke/ingress-lifecycle.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: edge-lifecycle
spec:
  ingressClassName: traefik
  rules:
    - host: $host
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: edge-smoke
                port:
                  name: http
EOF
  sed -i '/^  - ingress.yaml$/a\  - ingress-lifecycle.yaml' "$worktree/apps/edge-smoke/kustomization.yaml"
  git -C "$worktree" add apps/edge-smoke
  git -C "$worktree" commit -m 'test: add zero-touch edge hostname'
  commit="$(git -C "$worktree" rev-parse HEAD)"
  git -C "$worktree" push origin main
  kubectl -n argocd annotate application edge-smoke argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  for _ in $(seq 1 60); do curl -fsS --resolve "$host:443:10.10.30.237" "https://$host/health" >/dev/null && break; sleep 3; done
  curl -fsS --resolve "$host:443:10.10.30.237" "https://$host/health" >/dev/null
  git -C "$worktree" revert --no-edit "$commit"
  git -C "$worktree" push origin main
  kubectl -n argocd annotate application edge-smoke argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  for _ in $(seq 1 60); do kubectl -n edge-smoke get ingress edge-lifecycle >/dev/null 2>&1 || break; sleep 3; done
  if kubectl -n edge-smoke get ingress edge-lifecycle >/dev/null 2>&1; then die "temporary Ingress was not pruned"; fi
  after="$(resource_ids)"
  [[ "$before" == "$after" ]] || die "external edge identities changed during Git-only lifecycle"
  printf '%s\n' "$commit" >"$ROOT/.local/phase-04-zero-touch-proof"
  printf 'zero-touch hostname lifecycle passed with stable edge IDs %s\n' "$after"
}

case "${1:-}" in
  preflight) preflight ;;
  apply) apply_edge ;;
  status) status ;;
  prove-zero-touch) prove_zero_touch ;;
  *) die "usage: $0 {preflight|apply|status|prove-zero-touch}" ;;
esac
