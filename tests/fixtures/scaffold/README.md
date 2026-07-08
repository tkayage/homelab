# Scaffold offline test fixtures

These are **offline test fixtures, not deployable apps**. They exist solely to
drive `scripts/scaffold-verify.sh`, which runs the real `scaffold` binary against
each fixture and validates the full generation + GitOps pipeline **without a live
GitHub Actions run** (RESEARCH blocker B2 — the true push→build→GHCR→bump→Argo
end-to-end is deferred to the Phase 8 validation app).

## `t3-fixture/` — the T3 path

A minimal Next.js (T3) project: a `package.json` declaring a `next` dependency,
`next.config.js` with `output: 'standalone'`, and an `app/page.tsx` App-Router
marker. `detect` classifies it as T3, so the scaffolder **generates** a
Dockerfile, an `app/api/health/route.ts` health route, and the deploy workflow.

## `nont3-fixture/` — the SCAF-06 own-image path

A containerizable repo that already ships its **own** `Dockerfile` (with an
`EXPOSE 8080` line and a non-root `USER`) plus a tiny `server.js`. `detect`
classifies it as non-T3, so the scaffolder **validates and reuses** the existing
Dockerfile — it MUST be left byte-for-byte unchanged (SCAF-06) — and generates
only the deploy workflow.

## What the validator proves (offline)

Per fixture, `scripts/scaffold-verify.sh`:

1. builds the scaffolder;
2. scaffolds the fixture into a scratch app repo, publishing `apps/<slug>/` to a
   **local bare** gitops repo with a **throwaway** age keypair and a **dummy**
   pull token (no GitHub, no operator key, no real secret);
3. asserts the expected app-repo files were generated (and the non-T3 Dockerfile
   is byte-unchanged);
4. simulates the Argo CMP: SOPS-decrypts `pull-secret.enc.yaml`, runs
   `kustomize build`, and asserts the image is pinned;
5. runs `actionlint` on the generated workflow;
6. runs `kubectl apply --dry-run` on the rendered manifests.

Run it with `bash scripts/scaffold-verify.sh all` (or `t3` / `nont3`).
