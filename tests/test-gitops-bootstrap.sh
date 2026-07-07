#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
export KUBECONFIG
pass=0
check() { "$@" >/dev/null; pass=$((pass + 1)); }
contains() { rg -q "$1" "$2"; }

static_tests() {
  check bash -n "$ROOT/scripts/gitops-platform.sh"
  check contains 'preserveResourcesOnDeletion: true' "$ROOT/gitops/platform/applicationset.yaml"
  check contains 'prune: true' "$ROOT/gitops/platform/applicationset.yaml"
  check contains 'selfHeal: true' "$ROOT/gitops/platform/applicationset.yaml"
  check contains "path: apps/\\*" "$ROOT/gitops/platform/applicationset.yaml"
  check contains 'sops-kustomize-v1.0' "$ROOT/gitops/platform/applicationset.yaml"
  check contains 'ENC\[AES256_GCM' "$ROOT/gitops/apps/gitops-smoke/secret.enc.yaml"
  check contains 'preserveResourcesOnDeletion' "$ROOT/docs/gitops-bootstrap.md"
  if rg -n 'AGE-SECRET-KEY-|ghp_|github_pat_' "$ROOT/gitops" "$ROOT/infrastructure/kubernetes" "$ROOT/scripts" "$ROOT/docs"; then
    printf 'plaintext credential signature found\n' >&2; exit 1
  fi
  pass=$((pass + 1))
}

live_tests() {
  check kubectl get node
  check kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=2m
  [[ "$(kubectl -n argocd get application platform-root -o jsonpath='{.status.sync.status}')" == Synced ]]
  pass=$((pass + 1))
  [[ "$(kubectl -n argocd get application gitops-smoke -o jsonpath='{.status.sync.status}/{.status.health.status}')" == Synced/Healthy ]]
  pass=$((pass + 1))
  check kubectl -n gitops-smoke rollout status deployment/gitops-smoke --timeout=2m
  [[ -n "$(kubectl -n gitops-smoke get secret gitops-smoke -o jsonpath='{.data.token}')" ]]
  pass=$((pass + 1))
  [[ "$(kubectl -n argocd get application platform-root -o jsonpath='{.spec.syncPolicy.automated.prune}')" != true ]]
  pass=$((pass + 1))
  [[ "$(kubectl -n argocd get applicationset homelab-apps -o jsonpath='{.spec.preserveResourcesOnDeletion}')" == true ]]
  pass=$((pass + 1))
  [[ -f "$ROOT/.local/phase-03-rollback-proof" ]]
  pass=$((pass + 1))
}

case "${1:-}" in
  static) static_tests ;;
  live) static_tests; live_tests ;;
  *) printf 'usage: %s {static|live}\n' "$0" >&2; exit 1 ;;
esac
printf '%d GitOps checks passed\n' "$pass"
