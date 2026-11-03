#!/usr/bin/env bash
# Run a command with secrets injected from Infisical, authenticating as this
# host's machine identity (Universal Auth). Secrets reach the child process as
# environment variables only; they are never printed or written to disk.
#
#   scripts/infisical-run.sh [--env prod] [--path /] -- <command> [args...]
#
# Identity file (mode 0600), default ~/.config/homelab/infisical-agent.env:
#   INFISICAL_CLIENT_ID=...
#   INFISICAL_CLIENT_SECRET=...
#   INFISICAL_PROJECT_ID=...
set -euo pipefail

identity=${INFISICAL_IDENTITY_FILE:-$HOME/.config/homelab/infisical-agent.env}
export INFISICAL_API_URL=${INFISICAL_API_URL:-https://secrets.app.hapa.dev/api}
export INFISICAL_DISABLE_UPDATE_CHECK=true
env=prod path=/

fail() { printf 'ERROR %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --env) env=$2; shift 2 ;;
    --path) path=$2; shift 2 ;;
    --) shift; break ;;
    *) fail "unknown argument: $1 (put the command after --)" ;;
  esac
done
[[ $# -gt 0 ]] || fail "no command given"
command -v infisical >/dev/null || fail "infisical CLI is not installed"
[[ -r "$identity" ]] || fail "identity file is unavailable: $identity"
[[ $(stat -c %a "$identity") == 600 ]] || fail "identity file must be mode 600: $identity"

set -a; source "$identity"; set +a
: "${INFISICAL_CLIENT_ID:?}" "${INFISICAL_CLIENT_SECRET:?}" "${INFISICAL_PROJECT_ID:?}"

INFISICAL_TOKEN=$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" \
  --silent --plain) || fail "Universal Auth login failed"
export INFISICAL_TOKEN
unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET

exec infisical run --projectId="$INFISICAL_PROJECT_ID" --env="$env" --path="$path" --silent -- "$@"
