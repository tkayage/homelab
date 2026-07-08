// Command scaffold is the homelab project scaffolder CLI.
//
// It runs in-place inside an existing application repository and (once fully
// wired in later plans) generates the build/deploy plumbing for an app: a
// Dockerfile, a GitHub Actions workflow, and the per-app GitOps manifests
// committed to tkayage/gitops-homelab. This file is the cobra skeleton only —
// flag parsing and the preflight PATH check are wired here; the actual
// scaffolding is implemented in plan 06-07.
//
// Load-bearing assumptions (see scaffold/README.md, RESEARCH A1/A2):
//   - A1: module path github.com/tkayage/homelab/scaffold (repo has NO git remote)
//   - A2: GHCR org is "tkayage" -> images are ghcr.io/tkayage/<slug>
package main

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
)

// scaffoldOptions holds the parsed CLI flags for the scaffold command.
type scaffoldOptions struct {
	// slug overrides the slug derived from the repo/dir name.
	// Empty means "derive and validate from the working directory".
	slug string
	// port is the container port used for the non-T3 TCP probe and Service
	// targetPort. Defaults to 3000 (Next.js default).
	port int
	// dockerfile is the path to an existing Dockerfile for non-T3 detection.
	// Empty means "look at the repo root".
	dockerfile string
	// router selects the T3 health-route location: "app" (App Router) or
	// "pages" (Pages Router). Empty means auto-detect.
	router string
}

// requiredTools are the external binaries the scaffolder will shell out to once
// wired. The preflight helper asserts they resolve on PATH before doing work.
var requiredTools = []string{"git", "sops", "kustomize"}

// preflight is the Go equivalent of the gitops-platform.sh need() helper: it
// asserts every required external tool resolves on PATH and returns an error
// naming the first missing one. It performs no side effects and is safe to call
// before any file is written. Later plans call this at the top of the scaffold
// run; the skeleton exposes it so the dependency contract is explicit now.
func preflight(tools []string) error {
	for _, tool := range tools {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("missing required command %q on PATH (install it before running scaffold)", tool)
		}
	}
	return nil
}

// newScaffoldCmd builds the scaffold command with its flags wired to opts.
func newScaffoldCmd(opts *scaffoldOptions) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "scaffold",
		Short: "Generate build/deploy plumbing for an app repo (in-place)",
		Long: "Scaffold generates a Dockerfile, a GitHub Actions workflow, and the\n" +
			"per-app GitOps manifests for the current application repository. It is\n" +
			"run once inside the app repo; thereafter every push to main builds and\n" +
			"deploys via CI + Argo CD.\n\n" +
			"NOTE: this is a skeleton — it parses flags but performs no work yet\n" +
			"(wired in plan 06-07).",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			// Echo the parsed flags so --help and a dry invocation are useful,
			// then fail loudly rather than silently doing nothing.
			fmt.Fprintf(cmd.OutOrStdout(),
				"scaffold (skeleton): slug=%q port=%d dockerfile=%q router=%q\n",
				opts.slug, opts.port, opts.dockerfile, opts.router)
			return fmt.Errorf("not implemented — scaffolding is wired in plan 06-07")
		},
	}

	f := cmd.Flags()
	f.StringVar(&opts.slug, "slug", "", "override the slug derived from the repo/dir name")
	f.IntVar(&opts.port, "port", 3000, "container port for the non-T3 TCP probe / Service targetPort")
	f.StringVar(&opts.dockerfile, "dockerfile", "", "path to an existing Dockerfile for non-T3 detection")
	f.StringVar(&opts.router, "router", "", "T3 health-route location: app|pages (empty = auto-detect)")

	return cmd
}

// newRootCmd builds the root command. The root defaults to the scaffold command
// so `scaffold --slug foo` works without a subcommand, while leaving room for
// future subcommands (e.g. remove).
func newRootCmd() *cobra.Command {
	opts := &scaffoldOptions{}
	scaffoldCmd := newScaffoldCmd(opts)

	root := &cobra.Command{
		Use:   "scaffold",
		Short: "Homelab project scaffolder",
		Long: "Homelab project scaffolder — wire an app repo into the build → GHCR →\n" +
			"GitOps → Argo CD pipeline with one command.",
		SilenceUsage: true,
		// Delegate the bare `scaffold` invocation to the scaffold command.
		RunE: scaffoldCmd.RunE,
	}
	// Share the scaffold flags on the root so `scaffold --slug ...` binds them.
	root.Flags().AddFlagSet(scaffoldCmd.Flags())
	// Also expose scaffold as an explicit subcommand for discoverability and
	// future sibling commands.
	root.AddCommand(scaffoldCmd)

	return root
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
