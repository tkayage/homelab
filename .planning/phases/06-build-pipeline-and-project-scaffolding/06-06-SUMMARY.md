---
phase: 06-build-pipeline-and-project-scaffolding
plan: 06
subsystem: scaffolder
tags: [go, os-exec, git, sops, age, gitops, dockerconfigjson, security, integration-tests]
status: complete
dependency_graph:
  requires:
    - "scaffold/internal/manifests — Render(dir, Data) writing the five apps/<slug>/ gitops files (06-05)"
    - "scripts/gitops-platform.sh — proven load_credentials/sync_worktree/publish/preflight flow to port"
    - "gitops/.sops.yaml — age recipient age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq + encrypted_regex ^(data|stringData)$"
    - "sops v3.13.2 on PATH (06-01); operator age key ~/.config/homelab/age/keys.txt; operator GITHUB_TOKEN ~/.config/homelab/github.env"
  provides:
    - "scaffold/internal/gitops.Publish(cfg, slug, data) — clone/sync/preflight/render/encrypt/commit/push into gitops-homelab (os/exec git, NOT go-git)"
    - "scaffold/internal/gitops.EncryptPullSecret(appDir) — SOPS encrypt of the rendered pull secret + refuse-to-commit-plaintext guard"
    - "gitops.Config seam (RepoURL/Worktree/GitHubEnv/AgeRecipient/AgeKeyFile/SkipPreflight) for offline bare-repo + throwaway-key tests"
  affects:
    - "06-07 orchestrator calls gitops.Publish with the resolved manifests.Data{Slug, GHCROrg, Port, IsT3, Pull*} to register the app"
    - "06-08 exercises the live push to the real gitops-homelab with operator tokens end-to-end"
tech_stack:
  added: []
  patterns:
    - "os/exec git with x-access-token + GITHUB_TOKEN askpass (mode-0700 git-askpass.sh, GIT_TERMINAL_PROMPT=0) — ported verbatim from gitops-platform.sh"
    - "push preflight: GitHub API repos/<org>/<repo> permissions.push asserted BEFORE any write (T-06-16)"
    - "SOPS encrypt with explicit --age recipient + --encrypted-regex (deterministic regardless of cwd) rather than resolving a .sops.yaml creation rule"
    - "refuse-to-commit-plaintext: encrypt removes pull-secret.yaml, assertNoPlaintextSecret hard-fails before git add; also rejects a mis-named non-encrypted .enc.yaml (T-06-06)"
    - "offline integration test: local bare repo (git init --bare -b main) as fake origin + throwaway age keypair in t.TempDir(), SkipPreflight — no network"
key_files:
  created:
    - "scaffold/internal/gitops/gitops.go"
    - "scaffold/internal/gitops/gitops_test.go"
    - "scaffold/internal/gitops/sops.go"
    - "scaffold/internal/gitops/sops_test.go"
  modified: []
decisions:
  - "Committed in dependency order: sops.go (Task 2) first so the package compiles, then gitops.go (Task 1) whose Publish wires in encryptPullSecretWith + assertNoPlaintextSecret. Plan task numbering preserved in intent; commit order follows the compile dependency."
  - "SOPS encryption passes an explicit --age recipient + --encrypted-regex (not a .sops.yaml creation rule) so the scaffolder produces identical ciphertext shape regardless of the directory it runs from; output carries the same recipient + encrypted_regex ^(data|stringData)$ as live gitops-smoke/secret.enc.yaml"
  - "Public EncryptPullSecret(appDir) uses operator defaults; internal encryptPullSecretWith(appDir, recipient, keyFile) is the injectable core so tests round-trip through a throwaway age keypair and never touch the real operator key (T-06-17)"
  - "age-keygen is not on PATH in this environment, so the test uses a fixed dedicated throwaway age keypair (generated via X25519+bech32, verified to round-trip through sops 3.13.2) written to t.TempDir()/keys.txt — not the operator key at ~/.config/homelab/age/keys.txt"
  - "Publish commit message is product behavior `deploy(<slug>): register app` (Argo ApplicationSet auto-adopts apps/<slug>/); the whole platform copy from gitops-platform.sh is intentionally NOT ported — the scaffolder writes only apps/<slug>/"
  - "SkipPreflight config flag lets the offline test bypass the GitHub API preflight for a local bare origin; the real push always preflights push permission"
metrics:
  duration: "~20m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 4
  commits: 2
requirements: [SCAF-03, SCAF-04]
---

# Phase 06 Plan 06: GitOps Publish Flow + SOPS Pull-Secret Encryption Summary

Ported the proven `scripts/gitops-platform.sh` push flow to Go (`scaffold/internal/gitops`) and added the SOPS encryption step so the scaffolder can perform its one write into external state: clone/refresh `gitops-homelab`, render `apps/<slug>/`, SOPS-encrypt the dockerconfigjson pull secret, and commit+push `main` — the initial GitOps registration Argo's ApplicationSet auto-adopts. Uses `os/exec` git + `sops` (NOT go-git), reusing the exact `x-access-token` + `GITHUB_TOKEN` askpass convention. Both security guardrails are enforced and asserted: the push preflight (credential must have push permission before any write, T-06-16) and the refuse-to-commit-plaintext guard (only the SOPS ciphertext `pull-secret.enc.yaml` can ever be staged, T-06-06).

## What Was Built

**Task 2 — SOPS encryption + plaintext guard (`sops.go`, commit `626bf40`).**
- `EncryptPullSecret(appDir)` runs `sops --encrypt --age <recipient> --encrypted-regex ^(data|stringData)$` on the rendered plaintext `pull-secret.yaml`, writes `pull-secret.enc.yaml` (mode 0600), and removes the plaintext so only the ciphertext (matching `.*\.enc\.yaml$`) survives. Recipient + key default to the operator values from `gitops/.sops.yaml` / `~/.config/homelab/age/keys.txt`; the injectable `encryptPullSecretWith(appDir, recipient, keyFile)` core lets tests use a throwaway keypair.
- `assertNoPlaintextSecret(appDir)` hard-fails if a plaintext `pull-secret.yaml` still exists, and — defense in depth — rejects a `pull-secret.enc.yaml` that lacks SOPS markers (`ENC[` + `sops:`), catching a mis-named plaintext.
- `sops_test.go`: throwaway age keypair in `t.TempDir()`, encrypt then assert ciphertext carries `sops:` metadata, the expected age recipient, `encrypted_regex`, and an `ENC[` value while the plaintext token never appears; `sops -d` with the throwaway key recovers the original dockerconfigjson byte-for-byte. A second test drives the guard directly (fails while plaintext present, passes after encryption, rejects mis-named ciphertext).

**Task 1 — os/exec git publish flow (`gitops.go`, commit `9e03e3b`).**
- `Publish(cfg Config, slug string, data manifests.Data)`: `loadCredentials` (reads `GITHUB_TOKEN` from `github.env`, writes the mode-0700 `git-askpass.sh` answering `x-access-token`/token by case-match, sets `GIT_ASKPASS` + `GIT_TERMINAL_PROMPT=0`), `preflightPush` (GitHub API `permissions.push`), `syncWorktree` (clone when absent / `fetch origin main` + `checkout -B main` + `reset --hard origin/main`, set commit identity), `manifests.Render` into `apps/<slug>/`, `encryptPullSecretWith` + `assertNoPlaintextSecret`, then `git add apps/<slug>` → skip if nothing staged → commit `deploy(<slug>): register app` → `push origin main`.
- `Config` exposes `RepoURL`, `Worktree`, `GitHubEnv`, `AgeRecipient`, `AgeKeyFile`, `UserName/Email`, and `SkipPreflight` seams (all defaulted to the operator/gitops-platform.sh values) so tests point at a local bare repo offline.
- `gitops_test.go`: `git init --bare -b main` fake origin + temp `github.env` (dummy token) + throwaway age key + `SkipPreflight`; runs `Publish` and asserts `apps/myapp/{deployment,service,ingress,kustomization,pull-secret.enc}.yaml` landed on the origin's `main`, the plaintext `pull-secret.yaml` never reached the origin, the commit subject is `deploy(myapp): register app`, and the committed ciphertext is real SOPS (no plaintext token leak). A re-sync test confirms the fetch/reset path advances history by exactly one commit.

## Verification Results

- `go test -C scaffold ./internal/gitops/... -run TestGit` → ok (offline bare-repo publish + re-sync).
- `go test -C scaffold ./internal/gitops/... -run TestSops` → ok (real sops encrypt + `sops -d` round-trip; guard).
- `go build -C scaffold ./...`, `go vet -C scaffold ./...`, `gofmt -l scaffold/internal/gitops/` all clean.
- `go test -C scaffold ./...` → all packages ok (slug, detect, templates, manifests, gitops).
- Committed-ciphertext scan: the offline test asserts the pushed `pull-secret.enc.yaml` contains `ENC[` + `sops:` and NOT `dummy-throwaway-token`; the plaintext `pull-secret.yaml` is asserted absent from the origin tree.

## Deviations from Plan

**1. [Commit sequencing] Committed sops.go (Task 2) before gitops.go (Task 1).**
- **Reason:** `gitops.go`'s `Publish` calls `encryptPullSecretWith` + `assertNoPlaintextSecret` from `sops.go` (same package). Committing the git flow first would not compile. Committing the encryption unit first keeps every commit green.
- **Impact:** None on plan content — both tasks fully implemented and tested as specified. Only the commit order differs from the plan's task numbering.

No other deviations. No architectural (Rule 4) changes were needed.

## Threat Model Coverage

- **T-06-06 (Information Disclosure — plaintext dockerconfigjson in git, high, mitigate):** `EncryptPullSecret` removes the plaintext after producing the ciphertext; `assertNoPlaintextSecret` hard-fails before `git add`; the offline integration test asserts the plaintext `pull-secret.yaml` never reaches the origin and the committed `.enc.yaml` is real SOPS with no token leak. ✅ Mitigated.
- **T-06-16 (Spoofing / EoP — git push credential misuse, medium, mitigate):** the `x-access-token` + `GITHUB_TOKEN` askpass flow is ported verbatim; `preflightPush` asserts GitHub API `permissions.push` before any write (bypassed only for local bare-repo origins via `SkipPreflight`). ✅ Mitigated.
- **T-06-17 (Information Disclosure — age key / token leakage via test artifacts, low, mitigate):** tests use a dedicated throwaway age keypair + dummy tokens in `t.TempDir()`; the real operator key at `~/.config/homelab/age/keys.txt` is only referenced as a default, never copied, logged, or used by tests. ✅ Mitigated.

No new security surface beyond the plan's threat register was introduced.

## Known Stubs

None. The pull-secret token fields remain operator-provided (`manifests.Data.Pull*`, filled by the 06-07 orchestrator / 06-08 checkpoint); this plan supplies the encryption mechanism and its guardrails, which are complete and tested.

## Requirements Satisfied

- **SCAF-03 (register an app in gitops from one slug):** `Publish(cfg, slug, data)` renders and commits a complete `apps/<slug>/` set to `gitops-homelab` main; Argo's ApplicationSet auto-adopts it with no per-app Argo change.
- **SCAF-04 (private-GHCR pull credentials):** the dockerconfigjson pull secret is SOPS-encrypted to `pull-secret.enc.yaml` (same age recipient + `encrypted_regex` as the live CMP expects) with a hard guarantee no plaintext credential is ever committed.

## Commits

- `626bf40` feat(06-06): SOPS pull-secret encryption + refuse-to-commit-plaintext guard (T-06-06)
- `9e03e3b` feat(06-06): os/exec git publish flow to gitops-homelab (SCAF-03/04, T-06-16)

## Self-Check: PASSED

All four source files and the SUMMARY exist on disk; both task commits (`626bf40`, `9e03e3b`) are present in git history.
