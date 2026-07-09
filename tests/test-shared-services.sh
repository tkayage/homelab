#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

require_script_pattern() {
  local pattern=$1
  local description=$2
  if ! grep -Eq -- "$pattern" "$root/scripts/postgres-platform.sh"; then
    printf 'postgres-platform hardening check failed: %s\n' "$description" >&2
    return 1
  fi
}

postgres_platform_static_checks() {
  require_script_pattern 'validate_backup_subdir\(\)' 'POSTGRES_BACKUP_SUBDIR must be strict-validated'
  require_script_pattern 'require_beneath\(\)' 'backup and restore paths must use canonical containment checks'
  require_script_pattern 'realpath -e' 'canonical paths must be resolved with realpath'
  require_script_pattern 'reject_symlink_components\(\)' 'symlinked path components must be rejected'
  require_script_pattern 'mktemp -d' 'restore-test must copy the NAS artifact into a private temp directory'
  require_script_pattern 'sha256sum "\$snapshot"' 'restore-test must report a digest for the immutable snapshot'
  require_script_pattern 'gzip -t "\$snapshot"' 'restore-test must validate the immutable snapshot'
  require_script_pattern 'gunzip -c "\$snapshot"' 'restore-test must stream the immutable snapshot, not reopen the NAS path'
  require_script_pattern 'validate_scratch_name\(\)' 'POSTGRES_SCRATCH_NAME must be strict-validated'
  require_script_pattern 'validate_scratch_image\(\)' 'POSTGRES_SCRATCH_IMAGE must be strict-validated'
  require_script_pattern 'ssh_svc bash -s -- "\$scratch_name" "\$scratch_image"' 'remote Docker startup must pass scratch values as positional arguments'
  require_script_pattern 'ON_ERROR_STOP=1' 'SQL restore must fail on SQL errors'
  require_script_pattern 'restore failed; output follows' 'SQL restore failure output must be preserved'
  require_script_pattern '"\$dbs" -ge 1' 'restore-test must assert restored database/global state'
}

static_checks() {
  tofu -chdir="$root/infrastructure/opentofu/postgres" fmt -check
  tofu -chdir="$root/infrastructure/opentofu/services" fmt -check
  kubectl kustomize "$root/gitops/apps/shared-services" > /dev/null
  postgres_platform_static_checks
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
