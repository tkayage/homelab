# scaffold — homelab project scaffolder

A Go CLI that runs **in-place** inside an existing application repository and wires it
into the homelab build → GHCR → GitOps → Argo CD pipeline. Run once per app; thereafter
every push to `main` builds a versioned private image, CI bumps the image reference in
`tkayage/gitops-homelab`, and Argo CD reconciles it to a valid-TLS URL.

> Status: **skeleton**. This plan (06-01) bootstraps the module and the cobra CLI. The CLI
> parses its flags and runs a preflight PATH check but performs **no scaffolding yet** — the
> real work (slug derivation, T3 detection, template rendering, SOPS encrypt, gitops commit)
> is wired in later plans (06-02 … 06-07).

## Build & run

Do **not** commit the compiled binary — binaries in git are an anti-pattern and bloat
history. Build to the gitignored `.local/bin/` or run straight from source.

```bash
# Build (from the homelab repo root) to a gitignored location:
go build -C scaffold -o ../.local/bin/scaffold ./cmd/scaffold

# Or run directly from source during development:
go run -C scaffold ./cmd/scaffold --help
```

Flags:

| Flag           | Type   | Default | Purpose                                                        |
| -------------- | ------ | ------- | -------------------------------------------------------------- |
| `--slug`       | string | (derived) | Override the slug derived from the repo/dir name.           |
| `--port`       | int    | `3000`  | Container port for the non-T3 TCP probe / Service targetPort.  |
| `--dockerfile` | string | (repo root) | Path to an existing Dockerfile for non-T3 detection.      |
| `--router`     | string | (auto)  | T3 health-route location: `app` \| `pages` (empty = auto).     |

## Required tools on PATH

The scaffolder shells out to these (installed on the dev box in plan 06-01):

| Tool        | Version   | Used for                                             |
| ----------- | --------- | ---------------------------------------------------- |
| `git`       | 2.x       | Clone/commit/push the per-app manifests to gitops.   |
| `sops`      | 3.13.2    | Encrypt the generated `pull-secret.enc.yaml`.        |
| `kustomize` | v5.4.3    | Local kustomization validation; CI image-ref bump.   |

The CLI's preflight helper (`preflight()` in `cmd/scaffold/main.go`) asserts these resolve
on PATH before doing any work and fails with a clear message if one is missing.

## Load-bearing assumptions (confirm before publishing)

This repository currently has **no configured git remote** (`git remote -v` is empty), so the
following two values are **assumptions**, not verified facts. Confirm them before publishing
the module or running the scaffolder against real infrastructure:

- **A1 — module path `github.com/tkayage/homelab/scaffold`.** Baked into `go.mod`. Because the
  repo has no remote, `go install …@latest` will not resolve for an operator; build/run from
  source (above) instead. If the intended remote differs, edit `go.mod` and the import paths
  before publishing.
- **A2 — GHCR org is `tkayage`**, so images are `ghcr.io/tkayage/<slug>`. Strongly implied by
  the CONTEXT decisions and the `tkayage/gitops-homelab` GitOps repo, but not verified from a
  git remote. A later plan centralizes this org into a **single constant** so that if A2 is
  wrong it is trivial to change in one place rather than editing it across generated Dockerfiles,
  workflows, and manifests.

## Project layout

```
scaffold/
├── go.mod / go.sum              # module github.com/tkayage/homelab/scaffold; cobra v1.10.2 (A1)
└── cmd/scaffold/main.go         # cobra root + `scaffold` command, flags, preflight stub
```

Later plans add `internal/` packages (`slug`, `detect`, `gitops`, `report`) and, importantly,
embedded templates at **`internal/templates/files/`** — NOT at `scaffold/templates/`. Go's
`//go:embed` directive cannot reference paths outside the embedding package's directory (no
`..`), so template files must live under the package that embeds them.
