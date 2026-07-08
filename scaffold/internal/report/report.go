// Package report renders the scaffolder's SCAF-05 completion report: after a
// successful run it tells the operator exactly what was generated, where the app
// was registered in gitops, the URL the app will serve on, the Argo application
// name, and how to check its health.
//
// The output mirrors the printf-status style of scripts/gitops-platform.sh — a
// short, deterministic, human-scannable block written to an io.Writer. It is a
// pure formatter: Print performs no I/O beyond writing to w and no cluster or
// network calls (health reporting is a best-effort hint, since the dev box may
// lack cluster access).
package report

import (
	"fmt"
	"io"
)

// Result is everything the orchestrator (internal/scaffolder) resolves during a
// run and hands to Print. It is a plain data record — Print derives the rendered
// report entirely from these fields, so a given Result always prints identically.
type Result struct {
	// Slug is the canonical app identifier that drove the whole run.
	Slug string
	// IsT3 selects the health hint: T3 apps use an httpGet /api/health probe,
	// non-T3 apps use a TCP probe on Port.
	IsT3 bool
	// GeneratedFiles lists the app-repo files written, relative to the repo root
	// (e.g. "Dockerfile", ".github/workflows/deploy.yml", "app/api/health/route.ts").
	// For a non-T3 app the Dockerfile is NOT in this list (it was validated, not
	// generated — see ValidatedDockerfile).
	GeneratedFiles []string
	// ValidatedDockerfile is true for a non-T3 app whose existing Dockerfile was
	// validated and left byte-unchanged (SCAF-06). Print emits an explicit line so
	// the operator sees the Dockerfile was honored, not overwritten.
	ValidatedDockerfile bool
	// GitopsCommit is the gitops-homelab commit sha the run pushed (empty when the
	// run was a --dry-run that skipped publishing).
	GitopsCommit string
	// GitopsPath is the apps/<slug>/ path registered in gitops-homelab.
	GitopsPath string
	// URL is the expected public URL: https://<slug>.app.kayage.co.
	URL string
	// ArgoApp is the Argo CD application name (== Slug; the ApplicationSet adopts
	// apps/<slug>/ under that name).
	ArgoApp string
	// Port is the container port (used in the non-T3 TCP-probe health hint).
	Port int
	// Warnings surfaces any detection warnings (e.g. a non-T3 image missing a
	// non-root USER directive).
	Warnings []string
}

// Print writes the SCAF-05 completion report for r to w. Output is deterministic
// for a given Result. It never fails (write errors on an io.Writer such as
// os.Stdout are not actionable here) and performs no side effects beyond writing.
func Print(w io.Writer, r Result) {
	fmt.Fprintf(w, "==> scaffold complete: %s\n\n", r.Slug)

	fmt.Fprintln(w, "Generated app-repo files:")
	if r.ValidatedDockerfile {
		fmt.Fprintln(w, "  - validated existing Dockerfile (not overwritten)")
	}
	if len(r.GeneratedFiles) == 0 {
		fmt.Fprintln(w, "  (none)")
	}
	for _, f := range r.GeneratedFiles {
		fmt.Fprintf(w, "  - %s\n", f)
	}
	fmt.Fprintln(w)

	fmt.Fprintln(w, "GitOps registration (tkayage/gitops-homelab):")
	if r.GitopsCommit == "" {
		fmt.Fprintln(w, "  commit: (dry-run — not published)")
	} else {
		fmt.Fprintf(w, "  commit: %s\n", r.GitopsCommit)
	}
	fmt.Fprintf(w, "  path:   %s\n\n", r.GitopsPath)

	fmt.Fprintf(w, "Expected URL:     %s\n", r.URL)
	fmt.Fprintf(w, "Argo application: %s\n\n", r.ArgoApp)

	fmt.Fprintln(w, "Health check:")
	fmt.Fprintf(w, "  kubectl -n %s get deploy,pods\n", r.Slug)
	if r.IsT3 {
		fmt.Fprintln(w, "  probe: readiness/liveness httpGet /api/health")
	} else {
		fmt.Fprintf(w, "  probe: readiness/liveness TCP probe on port %d\n", r.Port)
	}

	if len(r.Warnings) > 0 {
		fmt.Fprintln(w, "\nWarnings:")
		for _, warn := range r.Warnings {
			fmt.Fprintf(w, "  - %s\n", warn)
		}
	}
}
