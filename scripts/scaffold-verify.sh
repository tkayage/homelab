#!/usr/bin/env bash
set -euo pipefail

# scaffold-verify.sh — offline end-to-end validator for the homelab scaffolder.
#
# For each committed fixture under tests/fixtures/scaffold/ it: builds the
# scaffolder, scaffolds the fixture into a scratch app repo publishing apps/<slug>/
# to a LOCAL bare gitops repo (throwaway age keypair + dummy pull token — no
# GitHub, no operator key, no real secret), then proves every downstream component
# offline: the generated app-repo files, the SOPS round-trip, `kustomize build`
# with a pinned image, `actionlint` on the workflow, and a `kubectl` dry-run.
#
# It runs FULLY OFFLINE (no GitHub, no live Actions). The true push→build→GHCR→
# bump→Argo loop is deferred to the Phase 8 validation app (06-RESEARCH blocker B2).
#
# Usage: scripts/scaffold-verify.sh {all|t3|nont3}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$ROOT/.local/kubeconfig-k3s-01}"
export KUBECONFIG

FIXTURES="$ROOT/tests/fixtures/scaffold"
SCAFFOLD_BIN="$ROOT/.local/bin/scaffold"

# A dedicated THROWAWAY age keypair for the offline publish (threat T-06-17: never
# touch the operator key; T-06-19: no real credential). Identical to the keypair
# the Go integration tests use so the encrypt path is exercised the same way.
readonly TEST_AGE_RECIPIENT="age168sywqplx2r3f6qm22yq90nv7duqrz42ka770lgd8pn0t0535syswqkldq"
readonly TEST_AGE_IDENTITY="AGE-SECRET-KEY-1R83EC9D2S6LGPPSFT4D5H2ALDT2VVJAVURC06MASUMDQ5P5MFJYSMX9EET"

# A clearly-dummy GHCR pull token — never a real read:packages secret (T-06-19).
readonly DUMMY_PULL_TOKEN="dummy-throwaway-pull-token"
readonly GHCR_ORG="tkayage"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing command: $1"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf 'ok: %s\n' "$*"; }

preflight() {
  need go; need git; need sops; need kustomize; need actionlint; need kubectl
  [[ -d "$FIXTURES" ]] || die "missing fixtures dir: $FIXTURES"
}

build_scaffolder() {
  mkdir -p "$ROOT/.local/bin"
  go build -C "$ROOT/scaffold" -o "$SCAFFOLD_BIN" ./cmd/scaffold
  ok "built scaffolder -> $SCAFFOLD_BIN"
}

# kube_dry_run_mode echoes "server" when the cluster is reachable via KUBECONFIG,
# else "client" (the fully-offline default). Server dry-run additionally validates
# against the live API server when it happens to be reachable.
kube_dry_run_mode() {
  if [[ -s "$KUBECONFIG" ]] && kubectl --request-timeout=5s version >/dev/null 2>&1; then
    printf 'server\n'
  else
    printf 'client\n'
  fi
}

# verify_fixture <fixture-name> <slug> <kind:t3|nont3>
verify_fixture() {
  local fixture="$1" slug="$2" kind="$3"
  local src="$FIXTURES/$fixture"
  [[ -d "$src" ]] || die "missing fixture: $src"

  printf '\n== %s (%s, slug=%s) ==\n' "$fixture" "$kind" "$slug"

  local scratch; scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' RETURN

  # --- scratch app repo (a copy of the fixture, git-inited) ---
  local app="$scratch/app"
  mkdir -p "$app"
  cp -a "$src/." "$app/"
  rm -rf "$app/.git"
  git -C "$app" init -q -b main
  git -C "$app" config user.name "scaffold-verify"
  git -C "$app" config user.email "verify@homelab.invalid"
  git -C "$app" add -A
  git -C "$app" commit -q -m "fixture: $fixture"

  # --- offline gitops origin + credential/age seams ---
  local origin="$scratch/gitops-origin.git"
  git init -q --bare -b main "$origin"

  local github_env="$scratch/github.env"
  printf 'export GITHUB_TOKEN=dummy-local-token\n' >"$github_env"
  chmod 600 "$github_env"

  local age_key="$scratch/keys.txt"
  printf '%s\n' "$TEST_AGE_IDENTITY" >"$age_key"
  chmod 600 "$age_key"

  local worktree="$scratch/.local/gitops-homelab"

  # Record the non-T3 Dockerfile digest BEFORE scaffolding (SCAF-06 byte-check).
  local df_before=""
  if [[ "$kind" == "nont3" ]]; then
    df_before="$(sha256sum "$app/Dockerfile" | awk '{print $1}')"
  fi

  # --- run the real scaffolder (full publish, fully offline) ---
  (
    cd "$app"
    "$SCAFFOLD_BIN" \
      --slug "$slug" \
      --ghcr-org "$GHCR_ORG" \
      --gitops-remote "$origin" \
      --gitops-worktree "$worktree" \
      --github-env "$github_env" \
      --age-recipient "$TEST_AGE_RECIPIENT" \
      --age-key-file "$age_key" \
      --skip-preflight \
      --pull-username "$GHCR_ORG" \
      --pull-password "$DUMMY_PULL_TOKEN" \
      >"$scratch/scaffold.out"
  ) || { cat "$scratch/scaffold.out" >&2; die "scaffold failed for $fixture"; }
  info "scaffolder ran (report in scaffold.out)"

  # --- (3) app-repo file assertions ---
  [[ -f "$app/.github/workflows/deploy.yml" ]] || die "missing generated workflow"
  if [[ "$kind" == "t3" ]]; then
    [[ -f "$app/Dockerfile" ]] || die "T3: expected a generated Dockerfile"
    grep -q "standalone" "$app/Dockerfile" || die "T3 Dockerfile is not the standalone build"
    [[ -f "$app/app/api/health/route.ts" ]] || die "T3: expected app/api/health/route.ts"
    ok "T3 app-repo files generated (Dockerfile + health route + workflow)"
  else
    local df_after; df_after="$(sha256sum "$app/Dockerfile" | awk '{print $1}')"
    [[ "$df_before" == "$df_after" ]] || die "SCAF-06 VIOLATION: non-T3 Dockerfile was modified"
    [[ ! -e "$app/app/api/health/route.ts" ]] || die "non-T3 must not generate a T3 health route"
    ok "SCAF-06: non-T3 Dockerfile byte-unchanged; only the workflow generated"
  fi

  # --- gitops registration assertions (on the bare origin) ---
  local tree; tree="$(git -C "$origin" ls-tree -r --name-only main)"
  local want
  for want in deployment.yaml service.yaml ingress.yaml kustomization.yaml pull-secret.enc.yaml; do
    grep -qx "apps/$slug/$want" <<<"$tree" || die "origin missing apps/$slug/$want"
  done
  grep -qx "apps/$slug/pull-secret.yaml" <<<"$tree" && die "plaintext pull-secret.yaml was committed"
  local enc; enc="$(git -C "$origin" show "main:apps/$slug/pull-secret.enc.yaml")"
  grep -q "ENC\[" <<<"$enc" || die "pull-secret.enc.yaml is not SOPS ciphertext"
  grep -q "$DUMMY_PULL_TOKEN" <<<"$enc" && die "dummy pull token leaked into committed ciphertext"
  ok "apps/$slug/ registered on origin; only SOPS ciphertext committed (no token leak)"

  # --- (4) simulate the Argo CMP: decrypt *.enc.yaml then kustomize build ---
  local cmp="$scratch/cmp"
  mkdir -p "$cmp"
  cp -a "$worktree/apps/$slug/." "$cmp/"
  local encrypted decrypted
  find "$cmp" -type f -name '*.enc.yaml' | while IFS= read -r encrypted; do
    decrypted="${encrypted%.enc.yaml}.yaml"
    SOPS_AGE_KEY_FILE="$age_key" sops --decrypt --output "$decrypted" "$encrypted"
    rm -f "$encrypted"
  done
  [[ -f "$cmp/pull-secret.yaml" ]] || die "CMP decrypt did not produce pull-secret.yaml"

  local rendered="$scratch/rendered.yaml"
  kustomize build "$cmp" >"$rendered" || die "kustomize build failed for apps/$slug"
  grep -q "ghcr.io/$GHCR_ORG/$slug:" "$rendered" || die "rendered image is not pinned (ghcr.io/$GHCR_ORG/$slug:<tag>)"
  ok "SOPS round-trip + kustomize build OK; image pinned to ghcr.io/$GHCR_ORG/$slug"

  # --- (5) actionlint on the generated workflow ---
  actionlint "$app/.github/workflows/deploy.yml" || die "actionlint reported problems in the generated workflow"
  ok "actionlint passed on the generated workflow"

  # --- (6) kubectl dry-run on the rendered manifests ---
  local mode; mode="$(kube_dry_run_mode)"
  kubectl apply --dry-run="$mode" -f "$rendered" >/dev/null || die "kubectl --dry-run=$mode rejected the manifests"
  ok "kubectl --dry-run=$mode validated the rendered manifests"

  printf 'PASS: %s\n' "$fixture"
  trap - RETURN
  rm -rf "$scratch"
}

t3()    { verify_fixture "t3-fixture" "t3-fixture" "t3"; }
nont3() { verify_fixture "nont3-fixture" "nont3-fixture" "nont3"; }

all() {
  build_scaffolder
  t3
  nont3
  printf '\nAll fixtures passed offline (build -> scaffold -> SOPS -> kustomize -> actionlint -> kubectl dry-run).\n'
}

main() {
  preflight
  case "${1:-}" in
    all)   all ;;
    t3)    build_scaffolder; t3 ;;
    nont3) build_scaffolder; nont3 ;;
    *)     die "usage: $0 {all|t3|nont3}" ;;
  esac
}

main "$@"
