---
phase: 06-build-pipeline-and-project-scaffolding
reviewed: 2026-07-08T00:00:00Z
depth: standard
files_reviewed: 36
files_reviewed_list:
  - scaffold/cmd/scaffold/main.go
  - scaffold/go.mod
  - scaffold/internal/detect/detect.go
  - scaffold/internal/detect/detect_test.go
  - scaffold/internal/gitops/gitops.go
  - scaffold/internal/gitops/gitops_test.go
  - scaffold/internal/gitops/sops.go
  - scaffold/internal/gitops/sops_test.go
  - scaffold/internal/manifests/manifests.go
  - scaffold/internal/manifests/manifests_test.go
  - scaffold/internal/report/report.go
  - scaffold/internal/report/report_test.go
  - scaffold/internal/scaffolder/scaffolder.go
  - scaffold/internal/scaffolder/scaffolder_test.go
  - scaffold/internal/slug/slug.go
  - scaffold/internal/slug/slug_test.go
  - scaffold/internal/templates/templates.go
  - scaffold/internal/templates/templates_test.go
  - scaffold/internal/templates/workflow_test.go
  - scaffold/internal/templates/files/Dockerfile.t3.tmpl
  - scaffold/internal/templates/files/health.page.ts.tmpl
  - scaffold/internal/templates/files/health.route.ts.tmpl
  - scaffold/internal/templates/files/workflow.deploy.yml.tmpl
  - scaffold/internal/templates/files/gitops/deployment.yaml.tmpl
  - scaffold/internal/templates/files/gitops/ingress.yaml.tmpl
  - scaffold/internal/templates/files/gitops/kustomization.yaml.tmpl
  - scaffold/internal/templates/files/gitops/pull-secret.yaml.tmpl
  - scaffold/internal/templates/files/gitops/service.yaml.tmpl
  - scripts/scaffold-verify.sh
  - tests/fixtures/scaffold/README.md
  - tests/fixtures/scaffold/nont3-fixture/Dockerfile
  - tests/fixtures/scaffold/nont3-fixture/server.js
  - tests/fixtures/scaffold/t3-fixture/app/page.tsx
  - tests/fixtures/scaffold/t3-fixture/next.config.js
  - tests/fixtures/scaffold/t3-fixture/package.json
findings:
  critical: 3
  warning: 8
  info: 8
  total: 19
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-07-08
**Depth:** standard
**Files Reviewed:** 36
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

Reviewed the full Go scaffolder subsystem (CLI, detect, slug, templates, manifests, gitops/SOPS publish, orchestrator, report), all generated-file templates, the offline E2E validator, and the test fixtures. `go vet` and `go test ./...` pass, but three Critical defects were found, all provable by tracing the real (non-test) operator path rather than the offline test path the suite exercises:

1. A real run commits a pull secret with an **empty password** — there is no operator-facing way to supply the actual GHCR token.
2. The plaintext dockerconfigjson secret is written **world-readable (0644)** into a persistent worktree and survives on disk when encryption fails.
3. The generated workflow's push-retry loop **exits 0 after exhausting retries** (empirically verified under Actions' `bash -e` semantics), silently dropping deploys under contention.

The security posture around SOPS staging (refuse-to-commit-plaintext guard), slug validation, template `missingkey=error`, and workflow action pinning is otherwise well constructed and well tested. Warnings cover an unpinned `curl | bash` in the generated workflow, misreported publish state, CWD-relative worktree placement inside the operator's app repo, silent overwrite of existing T3 files, and several logic edge cases.

## Critical Issues

### CR-01: Real (non-test) runs publish a pull secret with an empty password

**File:** `scaffold/internal/scaffolder/scaffolder.go:295-308`, `scaffold/cmd/scaffold/main.go:117-118`
**Issue:** `Options.PullPassword` is only settable via the hidden `--pull-password` flag, documented in both `main.go` ("offline test seam; dummy in tests") and `scaffolder.go` ("In tests they are dummy values") as a test-only seam. In a real operator run `opts.PullPassword` is `""`, so `publishGitops` computes `authB64 = base64("tkayage:")` and renders `pull-secret.yaml` with `"password":""`, which is then SOPS-encrypted and **committed to gitops-homelab**. Every scaffolded private-GHCR app will land with a non-functional `ghcr-pull` secret and fail with `ImagePullBackOff`. Nothing in `Run`, the report, or the docs surfaces this; the offline tests never hit it because they always pass a dummy token.
**Fix:** Fail closed (or prompt / read from a credential file) when the pull password is empty on a non-dry-run publish:

```go
if !opts.DryRun && opts.PullPassword == "" {
    return res, fmt.Errorf("scaffold: no GHCR pull token provided; " +
        "set it via <operator mechanism> so the committed pull secret can authenticate")
}
```

### CR-02: Plaintext pull secret written world-readable (0644) and persists on encryption failure

**File:** `scaffold/internal/templates/templates.go:66-75`, `scaffold/internal/manifests/manifests.go:60-66`, `scaffold/internal/gitops/gitops.go:139-150`
**Issue:** `manifests.Render` writes `pull-secret.yaml` — a plaintext dockerconfigjson containing the GHCR token — through `templates.RenderToFile`, which hardcodes mode `0o644`. The doc comment on `RenderToFile` claims "These are non-secret files… the SOPS-encrypted pull secret is generated and encrypted separately," but that is false: the plaintext secret itself flows through this 0644 path. The inversion is stark: the **ciphertext** gets `0o600` (`sops.go:86`) while the **plaintext** gets `0o644`. Worse, the file lands in the persistent worktree (default `.local/gitops-homelab/apps/<slug>/`), not a temp dir, and if `encryptPullSecretWith` fails (sops missing/erroring), `Publish` returns early leaving the world-readable plaintext token on disk indefinitely. A later run's `syncWorktree` does `reset --hard` but never `git clean`, so the untracked plaintext survives re-syncs too. The T-06-06 guard prevents it being *committed*, but the threat model ("no plaintext secret may ever be committed or logged") is undermined by leaving it readable on disk.
**Fix:** Write the pull secret at `0o600` (add a mode parameter or a `RenderToFileMode`), and guarantee cleanup on the failure path:

```go
if err := manifests.Render(appDir, data); err != nil { ... }
defer os.Remove(filepath.Join(appDir, "pull-secret.yaml")) // no-op after successful encrypt
```

### CR-03: Generated workflow's push-retry loop exits 0 when all retries fail — deploys silently lost

**File:** `scaffold/internal/templates/files/workflow.deploy.yml.tmpl:84-87`
**Issue:** The bump job's contention guard:

```bash
for i in 1 2 3; do
  git pull --rebase origin main && git push origin main && break
  sleep $((RANDOM % 5 + 2))
done
```

Under GitHub Actions' `bash -e -o pipefail`, a failing command inside an `&&` list does not trigger errexit (only the last command of an AND-OR list does, and `break` never fails). If all three pull/push attempts fail, the loop's final command is `sleep` (exit 0), so the **step and the workflow succeed while the gitops bump was never pushed** — Argo keeps running the old image with a green CI run. Empirically verified: `bash --noprofile --norc -e -o pipefail` running this shape exits 0 after three failures. This defeats the exact Pitfall-6 contention scenario the loop exists for.
**Fix:**

```bash
pushed=0
for i in 1 2 3; do
  if git pull --rebase origin main && git push origin main; then pushed=1; break; fi
  sleep $((RANDOM % 5 + 2))
done
if [ "$pushed" -ne 1 ]; then echo "::error::gitops push failed after 3 retries" >&2; exit 1; fi
```

(Also regenerate `testdata/workflow.golden` and add a structural-invariant assertion for the failure branch.)

## Warnings

### WR-01: Generated workflow installs kustomize via unpinned `curl | bash` from a moving branch

**File:** `scaffold/internal/templates/files/workflow.deploy.yml.tmpl:67-69`
**Issue:** `curl -sfL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash` executes an unpinned script fetched from `master` at run time inside a job holding `GITOPS_PUSH_TOKEN`. This directly contradicts the workflow's own supply-chain posture (T-06-03: every action pinned to a full commit SHA) — a compromised or changed install script runs with push access to the gitops repo. `TestWorkflowStructuralInvariants` checks `uses:` pins but has no rule for `run:` fetch-and-execute.
**Fix:** Download a versioned kustomize release tarball pinned by checksum (or pin the install script to a commit SHA and verify), e.g. fetch `kustomize_v5.4.3_linux_amd64.tar.gz` and compare `sha256sum` against a hardcoded digest before extracting.

### WR-02: Successful publish misreported as "(dry-run — not published)" when sha readback fails

**File:** `scaffold/internal/scaffolder/scaffolder.go:322-327`, `scaffold/internal/report/report.go:72-74`
**Issue:** `publishGitops` swallows `git rev-parse --short HEAD` errors and returns `"", nil`. `report.Print` keys on an empty `GitopsCommit` to print `commit: (dry-run — not published)`. So a run that actually pushed to gitops-homelab but failed the sha read reports it never published — the operator's mental model and the world diverge. Additionally, a no-op publish (`hasStagedChanges` false, nothing committed) still reads and reports the worktree HEAD sha as if this run pushed it.
**Fix:** Return a distinct sentinel (e.g. `"(published; sha unavailable)"`) or add a `Published bool` to `report.Result` so the dry-run message is driven by `DryRun`, not by an empty sha.

### WR-03: Default gitops worktree and askpass script are CWD-relative — created inside the operator's app repo

**File:** `scaffold/internal/scaffolder/scaffolder.go:45`, `scaffold/internal/gitops/gitops.go:42,183-194`
**Issue:** `defaultWorktree = ".local/gitops-homelab"` and the askpass script at `.local/git-askpass.sh` resolve relative to the process CWD, which for a real run is the app repo being scaffolded. The scaffolder therefore clones the entire gitops-homelab repo (including every app's manifests) *inside* the operator's app repo, where nothing gitignores `.local/` — one careless `git add -A` in the app repo commits the gitops clone. It is also inconsistent with `Options.Dir`: the repo root is resolved via `rev-parse` but the worktree ignores it.
**Fix:** Anchor the default to a stable per-user location (e.g. `os.UserHomeDir()/.local/state/homelab/gitops-homelab` or `os.UserCacheDir()`), or at minimum resolve it against the detected repo root and append `.local/` to the app repo's `.gitignore`.

### WR-04: T3 path silently overwrites an existing Dockerfile, health route, and workflow

**File:** `scaffold/internal/scaffolder/scaffolder.go:193-240`
**Issue:** `renderT3` unconditionally writes `Dockerfile`, the health route, and `.github/workflows/deploy.yml` into the app repo. SCAF-06's never-overwrite guarantee protects only non-T3 repos; a T3 repo with a hand-tuned Dockerfile or an existing `deploy.yml` gets clobbered with no warning, no backup, no `--force` gate. Uncommitted operator work is unrecoverable.
**Fix:** Before each write, `os.Stat` the destination; if it exists, either refuse with a `--force` escape hatch or at minimum append a warning to the report listing the overwritten files.

### WR-05: `--router` validated after the Dockerfile is already written — invalid flag leaves partial mutations

**File:** `scaffold/internal/scaffolder/scaffolder.go:195-211`
**Issue:** `renderT3` renders the Dockerfile first, then validates `routerOverride`, so `scaffold --router bogus` errors out *after* mutating the repo (Dockerfile written/overwritten). Flag validation must precede side effects. An invalid `--router` on a non-T3 repo is also silently ignored rather than rejected.
**Fix:** Validate `opts.Router ∈ {"", "app", "pages"}` in `Run` (or the cobra `PreRunE`) before step 5, and error on `--router` combined with a non-T3 detection.

### WR-06: `USER 0:0` / `USER root:root` incorrectly classified as non-root

**File:** `scaffold/internal/detect/detect.go:171-176`
**Issue:** The non-root check compares the whole `fields[1]` against `"root"` and `"0"`. Dockerfile `USER` accepts `user:group` syntax, so `USER 0:0` and `USER root:root` (both root) compare unequal and set `hasNonRootUser = true`, suppressing the security warning exactly when it applies. Later `USER` directives also don't override earlier ones (a `USER app` followed by `USER root` still reports non-root — the last directive wins in Docker).
**Fix:**

```go
user := strings.ToLower(fields[1])
if i := strings.IndexByte(user, ':'); i >= 0 { user = user[:i] }
hasNonRootUser = user != "root" && user != "0" // assign, don't just set true
```

Assigning (rather than latching `true`) also makes the final `USER` directive authoritative.

### WR-07: `syncWorktree` ignores checkout failure on the clone path; `reset --hard` never cleans untracked leftovers

**File:** `scaffold/internal/gitops/gitops.go:289,291-299`
**Issue:** On the fresh-clone path, `_ = git(cfg, env, "checkout", "-B", "main")` discards the error — a genuinely failed checkout (locked ref, dirty state, wrong default branch) proceeds straight into render/commit/push against whatever branch the clone landed on. On the re-sync path, `reset --hard origin/main` does not remove untracked files, so artifacts from a previously failed run (including a stale plaintext `pull-secret.yaml`, see CR-02) survive across syncs.
**Fix:** Handle the checkout error except for the known unborn-branch case (detect it explicitly), and run `git clean -fd -- apps/<slug>` (or clean the whole worktree) after reset.

### WR-08: `--pull-password` as a CLI flag exposes the token via process listing and shell history

**File:** `scaffold/cmd/scaffold/main.go:118`
**Issue:** If this flag is ever used with a real read:packages token (and per CR-01 it is currently the *only* way to supply one), the token is visible in `ps`/`/proc/*/cmdline` for the process lifetime and lands in shell history. Hidden-from-help does not mitigate either channel.
**Fix:** Accept the token via an environment variable or a file path (mirroring the `github.env` convention), and reject the flag form for non-dummy use.

## Info

### IN-01: Hand-rolled O(n·m) substring search reimplements `strings.Contains`

**File:** `scaffold/internal/gitops/sops.go:123-130`
**Issue:** `containsSub` is a byte-loop reimplementation of `strings.Contains`, which is already imported elsewhere in the package's tests and available.
**Fix:** Replace both call sites in `looksEncrypted` with `strings.Contains`.

### IN-02: `readGithubToken` mishandles inline comments and asymmetric quotes

**File:** `scaffold/internal/gitops/gitops.go:227-231`
**Issue:** `GITHUB_TOKEN=abc # comment` yields the literal token `abc # comment`; `strings.Trim(val, "\"'")` strips any mix of quote characters from both ends (e.g. `"abc'` → `abc`), diverging from shell semantics the file claims to parse.
**Fix:** Strip a trailing ` #...` segment (outside quotes) and only trim a matched leading/trailing quote pair.

### IN-03: Dockerfile scanner errors silently ignored

**File:** `scaffold/internal/detect/detect.go:148-179`
**Issue:** `bufio.Scanner` has a 64KB default line limit; an over-long line aborts the scan and `sc.Err()` is never checked, so EXPOSE/USER directives after that point are silently missed and detection falls back to defaults with no signal.
**Fix:** Check `sc.Err()` after the loop and surface it (or at least a warning); consider `sc.Buffer` with a larger cap.

### IN-04: `standaloneWarnings` matches the substring "standalone" anywhere, including comments

**File:** `scaffold/internal/scaffolder/scaffolder.go:271-283`
**Issue:** A `next.config.js` containing only `// TODO: enable standalone` passes the check; conversely, only the first config filename found in a fixed order is consulted. A false pass suppresses the warning that the generated Dockerfile depends on.
**Fix:** Match a tighter pattern, e.g. regex `output\s*:\s*['"]standalone['"]`.

### IN-05: Rendered manifests carry no namespace, but the report assumes namespace == slug

**File:** `scaffold/internal/templates/files/gitops/kustomization.yaml.tmpl`, `scaffold/internal/report/report.go:83`
**Issue:** No manifest or kustomization sets `namespace:`, so placement depends entirely on an unstated ApplicationSet destination convention, yet the report prints `kubectl -n <slug> get deploy,pods`. If the ApplicationSet destination is not `<slug>`, the health hint is wrong.
**Fix:** Either add `namespace: {{.Slug}}` to the kustomization (matching the ApplicationSet) or document the destination contract next to the report hint.

### IN-06: Pull credentials interpolated into JSON without escaping

**File:** `scaffold/internal/templates/files/gitops/pull-secret.yaml.tmpl:8`
**Issue:** `{{.PullUsername}}` / `{{.PullPassword}}` are spliced raw into a single-line JSON string inside a YAML literal block. A token containing `"` or `\` (or a newline) produces an invalid dockerconfigjson that fails only at image-pull time. GHCR tokens are currently alphanumeric, so this is latent.
**Fix:** Marshal the dockerconfigjson with `encoding/json` in Go and pass the finished string (or a `js`-escaped value) to the template.

### IN-07: Verify script leaks the scratch dir on failure; subshell locals are dead

**File:** `scripts/scaffold-verify.sh:71,152-157`
**Issue:** `trap 'rm -rf "$scratch"' RETURN` never fires when `die` calls `exit`, so every failed fixture run leaves a `mktemp -d` directory (containing the dummy-credential worktree) behind. Also `local encrypted decrypted` at line 152 are declared in the parent but only ever assigned inside the `find | while` pipeline subshell, so the declarations are dead code.
**Fix:** Add an `EXIT` trap for cleanup (or intentional retention with a message), and drop the dead `local` declarations or restructure with `< <(find …)`.

### IN-08: Nothing tells the operator to create the `GITOPS_PUSH_TOKEN` secret

**File:** `scaffold/internal/templates/files/workflow.deploy.yml.tmpl:65`, `scaffold/internal/report/report.go`
**Issue:** The generated workflow's bump job requires a `GITOPS_PUSH_TOKEN` repo secret, but neither the scaffolder nor the SCAF-05 report mentions it — the first real push to main will fail at the bump checkout with an opaque auth error.
**Fix:** Append a report line: "Add repo secret GITOPS_PUSH_TOKEN (fine-grained PAT, gitops-homelab Contents:write) before pushing to main."

---

_Reviewed: 2026-07-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
