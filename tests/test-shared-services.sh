#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

static_checks() {
  tofu -chdir="$root/infrastructure/opentofu/postgres" fmt -check
  tofu -chdir="$root/infrastructure/opentofu/services" fmt -check
  kubectl kustomize "$root/gitops/apps/shared-services" > /dev/null
  printf 'Static shared services tests passed\n'
}

live_checks() {
  static_checks
  echo "Running live checks in k8s cluster..."
  
  kubectl run shared-services-test -n shared-services --rm -i --restart=Never \
    --image=alpine:3.20 -- \
    sh -c "apk add --no-cache postgresql-client redis curl && \
      pg_isready -h postgres.shared-services.svc.cluster.local -p 5432 && \
      redis-cli -h valkey.shared-services.svc.cluster.local ping && \
      curl -fsS http://nats.shared-services.svc.cluster.local:8222/healthz && \
      curl -fsS http://debezium.shared-services.svc.cluster.local:8080/q/health"
      
  printf 'Live shared services tests passed\n'
}

case ${1:-static} in
  static) static_checks ;;
  live) live_checks ;;
  *) printf 'usage: %s {static|live}\n' "$0" >&2; exit 2 ;;
esac
