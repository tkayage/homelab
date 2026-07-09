---
phase: 06-build-pipeline-and-project-scaffolding
verified: 2026-07-09T08:26:00Z
status: gaps_found
score: 5/8
behavior_unverified: 1
overrides_applied: 0
gaps:
  - id: SCAF-04-PULL-SECRET-TOKEN
    requirement: SCAF-04
    severity: blocker
    description: "Real scaffolder runs can publish a GHCR pull secret with an empty password because PullPassword is only supplied by hidden offline-test flags."
  - id: SCAF-04-PLAINTEXT-SECRET-LIFETIME
    requirement: SCAF-04
    severity: blocker
    description: "Plaintext pull-secret.yaml is rendered through the shared 0644 template path and can remain in the persistent gitops worktree if SOPS encryption fails."
  - id: GITOPS-04-PUSH-RETRY-FALSE-SUCCESS
    requirement: GITOPS-04
    severity: blocker
    description: "The generated GitHub Actions gitops push retry loop exits 0 after all pull/push retries fail, so a deployment workflow can appear green while no GitOps bump was pushed."
---

# Phase 06 Verification

## Verdict

Phase 6 is **not yet verified complete**. The scaffolder implementation, templates,
and offline fixture harness pass their automated checks, but the production operator
path still has three release-blocking gaps that can produce non-functional private
image pulls, leave plaintext credentials on disk, or silently skip GitOps image bumps.

## Requirement Results

| Requirement | Status | Evidence |
|---|---|---|
| SCAF-01 | VERIFIED | Cobra scaffolder exists, validates slug/repo inputs, and the offline T3/non-T3 fixture runs complete through the real binary. |
| SCAF-02 | VERIFIED | T3 Dockerfile, health routes, and deploy workflow templates render and are covered by Go tests plus `scaffold-verify.sh`. |
| SCAF-03 | VERIFIED | GitOps manifests render under `apps/<slug>/`, SOPS ciphertext is committed, and kustomize builds in the offline harness. |
| SCAF-04 | FAILED (BLOCKER) | Generated workloads include probes, but private GHCR pull credential handling is unsafe/non-functional in real runs. |
| SCAF-05 | VERIFIED | The scaffolder reports generated files, GitOps path/commit, expected URL, Argo app, port, and warnings. |
| SCAF-06 | VERIFIED | The non-T3 fixture's Dockerfile remains byte-unchanged after scaffolding; T3 fixture generation passes offline validation. |
| GITOPS-03 | DEFERRED | Offline harness proves generated build/publish workflow shape, action pins, and image naming. Full live GHCR build is intentionally deferred to the Phase 8 validation app. |
| GITOPS-04 | FAILED (BLOCKER) | Generated CI can silently succeed without pushing the GitOps image bump when push contention persists. |

## Automated Checks

- `go test -C scaffold ./...` - PASS
- `bash scripts/scaffold-verify.sh all` - PASS
- Workflow push-loop reproduction under `bash --noprofile --norc -e -o pipefail` - FAILS SAFETY: the current retry loop exits 0 after repeated failures.

## Blocking Gaps

### 1. Real runs can publish an empty GHCR pull password

`scaffold/internal/scaffolder/scaffolder.go` builds the dockerconfigjson auth from
`opts.PullPassword`, but the only CLI path for that value is the hidden
`--pull-password` offline seam. A normal operator run therefore encrypts and commits
a pull secret whose password is empty, causing private GHCR pulls to fail.

**Required fix:** add an operator-safe credential input path, fail closed when a
non-dry-run publish lacks a pull token, and avoid passing real tokens through a
process-list-visible CLI flag.

### 2. Plaintext pull secret is world-readable and can persist on failure

`manifests.Render` writes `pull-secret.yaml` through `templates.RenderToFile`, which
uses mode `0644` for every template. If SOPS encryption fails, `gitops.Publish`
returns before `encryptPullSecretWith` removes the plaintext, leaving the
dockerconfigjson token in the persistent worktree.

**Required fix:** render the plaintext pull secret with restrictive permissions and
guarantee cleanup on all failure paths before returning from publish.

### 3. GitOps push retry loop reports success after all retries fail

The generated workflow uses:

```bash
for i in 1 2 3; do
  git pull --rebase origin main && git push origin main && break
  sleep $((RANDOM % 5 + 2))
done
```

Under GitHub Actions' `bash -e -o pipefail`, failures inside the `&&` list do not
abort the step, and the final `sleep` exits 0. A workflow can therefore finish green
without pushing the GitOps image bump.

**Required fix:** track a `pushed` flag and explicitly `exit 1` after exhausted
retries; update the workflow golden file and add a structural test for the failure
branch.

## Deferred Live Evidence

The full push -> GHCR image -> GitOps bump -> Argo deploy proof remains deferred to
the Phase 8 validation app, as documented in `06-VALIDATION.md` and `06-08-SUMMARY.md`.
That deferral is acceptable only after the three production-path blockers above are
fixed, because Phase 8 depends on the generated scaffolder contract.

## Next Action

Create gap-closure plans for Phase 6:

`$gsd-plan-phase 6 --gaps`

Then execute only the generated gap plans:

`$gsd-execute-phase 6 --gaps-only`

## Verification Complete

**Status:** `gaps_found`

**Score:** 5/8 requirements verified or acceptably deferred; 3 blocking gaps remain.
