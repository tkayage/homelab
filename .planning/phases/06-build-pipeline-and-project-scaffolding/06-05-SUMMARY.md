---
phase: 06-build-pipeline-and-project-scaffolding
plan: 05
subsystem: scaffolder
tags: [go, text-template, k8s-manifests, kustomize, sops, dockerconfigjson, gitops, golden-tests, tdd]
status: complete
dependency_graph:
  requires:
    - "scaffold/internal/templates — Render/RenderToFile + //go:embed all:files (from 06-03)"
    - "live analogs: gitops/apps/edge-smoke/{deployment,service,ingress}.yaml, gitops/apps/gitops-smoke/{kustomization,secret.enc}.yaml, gitops/.sops.yaml, infrastructure/kubernetes/argocd/cmp-plugin.yaml"
    - "06-04 workflow image string ghcr.io/{{.GHCROrg}}/{{.Slug}} (byte-identical bump target)"
  provides:
    - "scaffold/internal/manifests — Render(dir, Data) writing the five apps/<slug>/ gitops files"
    - "files/gitops/{deployment,service,ingress,kustomization,pull-secret}.yaml.tmpl — slug-parameterized manifest templates under the shared embed FS"
    - "testdata/apps-slug.golden.txt — kustomize-build regression fixture (fully transformed, image pinned)"
  affects:
    - "06-06 encrypts the rendered plaintext pull-secret.yaml in place -> pull-secret.enc.yaml (SOPS) and adds a refuse-to-commit-plaintext guard"
    - "06-07 orchestrator calls manifests.Render with the resolved Data{Slug, GHCROrg, Port, IsT3, Pull*} to populate the app dir before commit/push"
tech_stack:
  added: []
  patterns:
    - "SOPS filename indirection: kustomization resources reference the DECRYPTED pull-secret.yaml while the on-disk ciphertext is pull-secret.enc.yaml (CMP decrypts *.enc.yaml->*.yaml then runs stock kustomize build)"
    - "kustomize images: transformer name byte-identical to the Deployment image so `kustomize edit set image` resolves instead of no-oping to :latest"
    - "probe shape gated on a template bool ({{if .IsT3}} httpGet /api/health {{else}} tcpSocket {{end}}) rendered on both readiness and liveness"
    - "kustomize-build golden: shell out to the pinned kustomize on PATH, lock the fully transformed output byte-for-byte, skip gracefully if kustomize absent"
    - "secret token fields are template placeholders; no plaintext token is ever written to a committed file (encryption is a downstream plan's job)"
key_files:
  created:
    - "scaffold/internal/manifests/manifests.go"
    - "scaffold/internal/manifests/manifests_test.go"
    - "scaffold/internal/manifests/testdata/apps-slug.golden.txt"
    - "scaffold/internal/templates/files/gitops/deployment.yaml.tmpl"
    - "scaffold/internal/templates/files/gitops/service.yaml.tmpl"
    - "scaffold/internal/templates/files/gitops/ingress.yaml.tmpl"
    - "scaffold/internal/templates/files/gitops/kustomization.yaml.tmpl"
    - "scaffold/internal/templates/files/gitops/pull-secret.yaml.tmpl"
  modified: []
decisions:
  - "Deployment container named `app` (RESEARCH §6), image name-only ghcr.io/<org>/<slug> — the tag is owned exclusively by the kustomization images: transformer (Pitfall 2)"
  - "Both readiness and liveness probes share the same gated block: T3 -> httpGet /api/health on port http; non-T3 -> tcpSocket on port http (named port resolves to the resolved containerPort)"
  - "Render writes pull-secret.yaml as PLAINTEXT (the decrypted name the kustomization references); 06-06 encrypts in place to pull-secret.enc.yaml. Writing the decrypted name is what lets `kustomize build` succeed offline in the test (simulating the CMP post-decrypt state)"
  - "Pull-secret token/auth are template fields (PullUsername/PullPassword/PullAuthB64); tests use a dummy token, no real read:packages PAT is committed"
  - "kustomize-build golden generated from the pinned kustomize v5.4.3 on PATH; TestKustomizeBuild t.Skip()s if kustomize is unavailable so the suite stays portable"
metrics:
  duration: "~6m"
  completed: 2026-07-08
  tasks_completed: 2
  files_created: 8
  commits: 4
requirements: [SCAF-03, SCAF-04]
---

# Phase 06 Plan 05: Per-App GitOps Manifest Templates + manifests.Render Summary

Authored the five slug-parameterized GitOps manifest templates the scaffolder commits to `apps/<slug>/` in gitops-homelab (Deployment, Service, Ingress, Kustomization, dockerconfigjson pull Secret), plus `manifests.Render(dir, Data)` that writes them, and proved the result renders cleanly through a real `kustomize build`. Both load-bearing pitfalls are enforced and asserted: SOPS filename indirection (kustomization references the decrypted `pull-secret.yaml`, never `pull-secret.enc.yaml`) and image-name match (the Deployment `image:` and the kustomization `images[].name` are byte-identical to the 06-04 bump target).

## What Was Built

**Task 1 — deployment/service/ingress templates + manifests.Render (RED `4e54262` -> GREEN `ef66dc2`).**
- New `internal/manifests` package with `Data{Slug, GHCROrg, Port, IsT3, PullUsername, PullPassword, PullAuthB64}` and `Render(dir string, data Data) error`, which renders each embedded `gitops/*.tmpl` through the shared `templates.RenderToFile` seam into the app dir.
- `deployment.yaml.tmpl` mirrors the live edge-smoke shape (`app.kubernetes.io/name` labels on metadata/selector/template, named `http` port, bounded resources) with the CONTEXT/RESEARCH §6 divergences: name-only image `ghcr.io/{{.GHCROrg}}/{{.Slug}}` (tag owned by the transformer — Pitfall 2), `imagePullSecrets: [{name: ghcr-pull}]` (edge-smoke has none, its image is public), `containerPort: {{.Port}}` (Next default 3000), `strategy.type: RollingUpdate`, and resource defaults `requests {cpu 25m, memory 128Mi}` / `limits {cpu 500m, memory 512Mi}`. The readiness and liveness probes are gated on `{{if .IsT3}}` — T3 gets `httpGet /api/health` on port `http`, non-T3 gets `tcpSocket` on the same named port.
- `service.yaml.tmpl` and `ingress.yaml.tmpl` copy edge-smoke verbatim, slug-parameterized: Service `port 80 -> targetPort http`; Ingress `ingressClassName traefik`, host `{{.Slug}}.app.kayage.co`, `pathType Prefix`, backend service port name `http`.

**Task 2 — kustomization + pull-secret templates, image match, kustomize-build proof (RED `84db632` -> GREEN `982aef9`).**
- `kustomization.yaml.tmpl`: `resources` lists `deployment.yaml, service.yaml, ingress.yaml, pull-secret.yaml` — the **decrypted** name (Pitfall 1, verified against live `gitops-smoke` whose kustomization references `secret.yaml` while the file is `secret.enc.yaml`). Adds an `images:` transformer entry `name: ghcr.io/{{.GHCROrg}}/{{.Slug}}` / `newTag: latest` — the name is byte-identical to the Deployment image so the CI `kustomize edit set image` bump resolves.
- `pull-secret.yaml.tmpl`: a `kubernetes.io/dockerconfigjson` Secret named `ghcr-pull`, with the `.dockerconfigjson` auths body filled by template fields (`PullUsername`/`PullPassword`/`PullAuthB64`). No real token is present — encryption and the real read:packages PAT are 06-06's responsibility.
- `Render` extended to write all five files. Tests render a full `apps/<slug>/` into `t.TempDir()`, assert the SOPS indirection and the image-name match, then shell out to the pinned `kustomize build` on the rendered dir (the plaintext `pull-secret.yaml` simulates the CMP's post-decrypt state), assert exit 0 with the image pinned to `:latest`, and lock the full build output to `testdata/apps-slug.golden.txt`.

## Verification Results

- `go test -C scaffold ./internal/manifests/...` -> ok (8 tests: deployment T3/non-T3, service, ingress, SOPS indirection, image-name match, pull-secret, kustomize-build+golden).
- `kustomize build` on a rendered app dir exits 0 and pins `image: ghcr.io/testorg/myapp:latest` (transformer applied). Golden locked byte-for-byte.
- `go build -C scaffold ./...` and `go vet -C scaffold ./...` clean; `go test -C scaffold ./...` all packages ok (slug, detect, templates, manifests).
- Token scan of committed files: only template placeholders (`{{.Pull*}}`) and a dummy `dummy-token`/`dGVzdG9yZzpkdW1teS10b2tlbg==` in the golden — no real PAT.
- Post-commit deletion check: none. Throwaway `cmd/goldgen` used to generate the golden was removed; no strays left under the module.

## Deviations from Plan

None — plan executed as written. The pull-secret is written as plaintext `pull-secret.yaml` (the decrypted name) exactly as the plan and RESEARCH specify; SOPS encryption is explicitly deferred to 06-06.

## TDD Gate Compliance

Both tasks are `tdd="true"` and followed RED -> GREEN with distinct commits:
- Task 1: RED `4e54262` `test(06-05)` (tests fail — Render stub writes nothing) -> GREEN `ef66dc2` `feat(06-05)` (three templates + Render).
- Task 2: RED `84db632` `test(06-05)` (kustomization/pull-secret/kustomize-build tests fail on missing files) -> GREEN `982aef9` `feat(06-05)` (two templates + Render extended + golden).
No test passed unexpectedly during either RED phase (all failed on absent rendered files). No REFACTOR commits were needed.

## Threat Model Coverage

- **T-06-06 (Information Disclosure — pull-secret plaintext, high, mitigate):** the plaintext dockerconfigjson shape is rendered only into `t.TempDir()` for the build test; the committed template carries `{{.Pull*}}` placeholders, and the golden carries a dummy token. No real token in any committed file. SOPS encryption + a refuse-to-commit-plaintext guard land in 06-06. ✅ Mitigated (this plan's portion).
- **T-06-14 (Tampering — SOPS filename indirection, high, mitigate):** kustomization `resources` references the decrypted `pull-secret.yaml`; a test asserts `pull-secret.enc.yaml` never appears. ✅ Mitigated.
- **T-06-15 (Tampering — image-name mismatch, medium, mitigate):** the Deployment image and kustomization `images[].name` are extracted and compared byte-for-byte in `TestImageNameMatch`; a bump can never silently no-op to `:latest`. ✅ Mitigated.

No new security surface beyond the plan's threat register was introduced.

## Known Stubs

The pull-secret token fields (`PullUsername`/`PullPassword`/`PullAuthB64`) are intentional template placeholders. They are NOT a rendering stub — the real read:packages token is operator-provided and the file is SOPS-encrypted in plan **06-06** (the plan's own threat register T-06-06 documents this hand-off). No UI/data stub exists in this plan.

## Requirements Satisfied

- **SCAF-03 (gitops config from one slug):** a single slug renders a complete, buildable `apps/<slug>/` manifest set (deployment/service/ingress/kustomization/pull-secret), proven via `kustomize build`.
- **SCAF-04 (health probes + private-GHCR pull credentials):** the Deployment carries T3 `httpGet /api/health` (or non-T3 `tcpSocket`) readiness+liveness probes and `imagePullSecrets: ghcr-pull`, backed by the dockerconfigjson pull Secret template.

## Commits

- `4e54262` test(06-05): failing tests for manifests.Render deployment/service/ingress
- `ef66dc2` feat(06-05): deployment/service/ingress templates + manifests.Render (SCAF-04)
- `84db632` test(06-05): failing tests for kustomization SOPS indirection, image match, kustomize build
- `982aef9` feat(06-05): kustomization + dockerconfigjson pull-secret templates; kustomize build proof (SCAF-03)

## Self-Check: PASSED
