#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
GITHUB_ENV="${GITHUB_ENV:-/home/tonny/.config/homelab/github.env}"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/home/tonny/.config/homelab/age/keys.txt}"
GITOPS_REPO="tkayage/gitops-homelab"
GITOPS_URL="https://github.com/${GITOPS_REPO}.git"
WORKTREE="$ROOT/.local/gitops-homelab"
ARGO_VERSION="v3.4.2"
ARGO_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_VERSION}/manifests/install.yaml"
CMP_IMAGE="homelab/argocd-sops:v3.4.2-sops3.13.2"
export KUBECONFIG

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }

load_credentials() {
  [[ -r "$GITHUB_ENV" ]] || die "missing GitHub credentials: $GITHUB_ENV"
  set -a
  # shellcheck disable=SC1090
  source "$GITHUB_ENV"
  set +a
  [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN is not set"
  export GIT_USERNAME=x-access-token GIT_PASSWORD="$GITHUB_TOKEN"
  mkdir -p "$ROOT/.local"
  cat >"$ROOT/.local/git-askpass.sh" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "$GIT_USERNAME" ;;
  *) printf '%s\n' "$GIT_PASSWORD" ;;
esac
EOF
  chmod 700 "$ROOT/.local/git-askpass.sh"
  export GIT_ASKPASS="$ROOT/.local/git-askpass.sh" GIT_TERMINAL_PROMPT=0
}

preflight() {
  need git; need kubectl; need curl; need jq; need docker; need ssh
  [[ -s "$KUBECONFIG" ]] || die "missing kubeconfig: $KUBECONFIG"
  [[ -s "$AGE_KEY_FILE" ]] || die "missing age recovery key: $AGE_KEY_FILE"
  [[ "$(stat -c %a "$AGE_KEY_FILE")" == 600 ]] || die "age key must have mode 600"
  load_credentials
  kubectl get node >/dev/null
  curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$GITOPS_REPO" | grep -q '"push": true' ||
    die "credential cannot push to $GITOPS_REPO"
  printf 'preflight passed\n'
}

prepare_cmp_image() {
  local source="$ROOT/.local/downloads/sops-v3.13.2.linux.amd64"
  if [[ ! -s "$source" ]]; then
    mkdir -p "$(dirname "$source")"
    curl -fL --retry 5 -o "$source" \
      'https://github.com/getsops/sops/releases/download/v3.13.2/sops-v3.13.2.linux.amd64'
  fi
  echo "154dfe4cd70554bdd82b98e4cd4acf191d43d01ead6f00a73477aa44c4ac42ef  $source" | sha256sum -c - >/dev/null
  install -m 0755 "$source" "$ROOT/infrastructure/kubernetes/argocd/sops"
  trap 'rm -f "$ROOT/infrastructure/kubernetes/argocd/sops"' RETURN
  docker build --quiet -t "$CMP_IMAGE" \
    -f "$ROOT/infrastructure/kubernetes/argocd/Dockerfile.sops" \
    "$ROOT/infrastructure/kubernetes/argocd" >/dev/null
  docker save "$CMP_IMAGE" |
    ssh -o BatchMode=yes ubuntu@10.10.30.102 'sudo k3s ctr images import -' >/dev/null
}

sync_worktree() {
  load_credentials
  if [[ ! -d "$WORKTREE/.git" ]]; then
    rm -rf "$WORKTREE"
    git clone "$GITOPS_URL" "$WORKTREE"
  else
    git -C "$WORKTREE" fetch origin main
    git -C "$WORKTREE" checkout main
    git -C "$WORKTREE" reset --hard origin/main
  fi
  rm -rf "$WORKTREE/apps" "$WORKTREE/platform" "$WORKTREE/.sops.yaml"
  cp -a "$ROOT/gitops/apps" "$ROOT/gitops/platform" "$ROOT/gitops/.sops.yaml" "$WORKTREE/"
  git -C "$WORKTREE" config user.name "Homelab GitOps Operator"
  git -C "$WORKTREE" config user.email "gitops@homelab.invalid"
}

publish() {
  sync_worktree
  git -C "$WORKTREE" add .sops.yaml apps platform
  if ! git -C "$WORKTREE" diff --cached --quiet; then
    git -C "$WORKTREE" commit -m "bootstrap: reconcile homelab platform"
    git -C "$WORKTREE" push origin main
  fi
  printf 'GitOps repository is current\n'
}

install_argocd() {
  prepare_cmp_image
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd --server-side --force-conflicts -f "$ARGO_MANIFEST"
  for resource in $(kubectl -n argocd get deployments,statefulsets -o name); do
    kubectl -n argocd patch "$resource" --type=json \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' >/dev/null
    init_count="$(kubectl -n argocd get "$resource" -o json | jq '.spec.template.spec.initContainers // [] | length')"
    for ((index = 0; index < init_count; index++)); do
      kubectl -n argocd patch "$resource" --type=json \
        -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/initContainers/$index/imagePullPolicy\",\"value\":\"IfNotPresent\"}]" >/dev/null
    done
  done
  kubectl apply -f "$ROOT/infrastructure/kubernetes/argocd/cmp-plugin.yaml"
  kubectl -n argocd create secret generic sops-age \
    --from-file="keys.txt=$AGE_KEY_FILE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n argocd create secret generic gitops-homelab-repository \
    --from-literal="url=$GITOPS_URL" \
    --from-literal="username=x-access-token" \
    --from-literal="password=$GITHUB_TOKEN" \
    --dry-run=client -o yaml |
    kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml |
    kubectl apply -f -
  kubectl -n argocd patch deployment argocd-repo-server --type=strategic \
    --patch-file "$ROOT/infrastructure/kubernetes/argocd/repo-server-patch.yaml"
  container_count="$(kubectl -n argocd get deployment/argocd-repo-server -o json | jq '.spec.template.spec.containers | length')"
  for ((index = 0; index < container_count; index++)); do
    image="$(kubectl -n argocd get deployment/argocd-repo-server -o json | jq -r ".spec.template.spec.containers[$index].image")"
    [[ "$image" == "$CMP_IMAGE" ]] && policy=Never || policy=IfNotPresent
    kubectl -n argocd patch deployment/argocd-repo-server --type=json \
      -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/$index/imagePullPolicy\",\"value\":\"$policy\"}]" >/dev/null
  done
  kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=10m
  kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
}

apply_root() {
  kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $GITOPS_URL
    targetRevision: main
    path: platform
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
EOF
  kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
}

wait_healthy() {
  local deadline=$((SECONDS + 600)) sync health
  while (( SECONDS < deadline )); do
    sync="$(kubectl -n argocd get application gitops-smoke -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kubectl -n argocd get application gitops-smoke -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    if [[ "$sync" == Synced && "$health" == Healthy ]]; then
      kubectl -n gitops-smoke rollout status deployment/gitops-smoke --timeout=2m
      return 0
    fi
    sleep 5
  done
  kubectl -n argocd get applications || true
  die "gitops-smoke did not become Synced/Healthy"
}

status() {
  kubectl -n argocd get applications
  kubectl -n gitops-smoke get deployment,pod,secret 2>/dev/null || true
}

bootstrap() {
  preflight
  publish
  install_argocd
  apply_root
  wait_healthy
  status
}

prove_rollback() {
  preflight
  sync_worktree
  local manifest="$WORKTREE/apps/gitops-smoke/deployment.yaml" bad_commit
  sed -i 's#nginx:1.29.0-alpine#nginx:0.0.0-does-not-exist#' "$manifest"
  git -C "$WORKTREE" add apps/gitops-smoke/deployment.yaml
  git -C "$WORKTREE" commit -m "test: introduce controlled bad image"
  bad_commit="$(git -C "$WORKTREE" rev-parse HEAD)"
  git -C "$WORKTREE" push origin main
  kubectl -n argocd annotate application gitops-smoke argocd.argoproj.io/refresh=hard --overwrite
  local deadline=$((SECONDS + 300)) observed=false image
  while (( SECONDS < deadline )); do
    image="$(kubectl -n gitops-smoke get deployment gitops-smoke -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
    [[ "$image" == nginx:0.0.0-does-not-exist ]] && { observed=true; break; }
    sleep 5
  done
  [[ "$observed" == true ]] || die "controlled bad revision was not reconciled"
  git -C "$WORKTREE" revert --no-edit "$bad_commit"
  git -C "$WORKTREE" push origin main
  kubectl -n argocd annotate application gitops-smoke argocd.argoproj.io/refresh=hard --overwrite
  wait_healthy
  mkdir -p "$ROOT/.local"
  printf '%s\n' "$bad_commit" >"$ROOT/.local/phase-03-rollback-proof"
  printf 'rollback proof passed\n'
}

ui() {
  printf 'Argo CD UI: https://127.0.0.1:8443 (self-signed certificate)\n'
  exec kubectl -n argocd port-forward service/argocd-server 8443:443
}

case "${1:-}" in
  preflight) preflight ;;
  publish) preflight; publish ;;
  bootstrap) bootstrap ;;
  status) status ;;
  prove-rollback) prove_rollback ;;
  ui) ui ;;
  *) die "usage: $0 {preflight|publish|bootstrap|status|prove-rollback|ui}" ;;
esac
