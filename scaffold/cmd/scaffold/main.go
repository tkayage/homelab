// Command scaffold is the homelab project scaffolder CLI.
//
// It runs in-place inside an existing application repository and generates the
// build/deploy plumbing for an app: a Dockerfile (T3) or a validated existing
// Dockerfile (non-T3), a GitHub Actions workflow, and the per-app GitOps
// manifests committed to tkayage/gitops-homelab. The actual orchestration lives
// in internal/scaffolder; this file is the cobra front-end that parses flags into
// scaffolder.Options, calls scaffolder.Run, and prints the SCAF-05 report.
//
// Load-bearing assumptions (see scaffold/README.md, RESEARCH A1/A2):
//   - A1: module path github.com/tkayage/homelab/scaffold (repo has NO git remote)
//   - A2: GHCR org is "tkayage" -> images are ghcr.io/tkayage/<slug>
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/tkayage/homelab/scaffold/internal/report"
	"github.com/tkayage/homelab/scaffold/internal/scaffolder"
)

// scaffoldOptions holds the parsed CLI flags for the scaffold command.
type scaffoldOptions struct {
	// slug overrides the slug derived from the repo/dir name.
	// Empty means "derive and validate from the working directory".
	slug string
	// port is the container port used for the non-T3 TCP probe and Service
	// targetPort. 0 means "parse EXPOSE / default 3000".
	port int
	// dockerfile is the path to an existing Dockerfile for non-T3 detection.
	// Empty means "look at the repo root".
	dockerfile string
	// router selects the T3 health-route location: "app" (App Router) or
	// "pages" (Pages Router). Empty means auto-detect.
	router string
	// ghcrOrg is the SINGLE centralized GHCR org threaded into both the workflow
	// image and the gitops manifests (default "tkayage").
	ghcrOrg string
	// dryRun renders the app-repo files but skips the gitops publish.
	dryRun bool
	// gitopsRemote overrides the gitops-homelab clone URL (empty = the real repo).
	gitopsRemote string
}

// newScaffoldCmd builds the scaffold command with its flags wired to opts.
func newScaffoldCmd(opts *scaffoldOptions) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "scaffold",
		Short: "Generate build/deploy plumbing for an app repo (in-place)",
		Long: "Scaffold generates a Dockerfile (or validates an existing one), a\n" +
			"GitHub Actions workflow, and the per-app GitOps manifests for the\n" +
			"current application repository, then registers apps/<slug>/ in\n" +
			"gitops-homelab. It is run once inside the app repo; thereafter every\n" +
			"push to main builds and deploys via CI + Argo CD.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			res, err := scaffolder.Run(scaffolder.Options{
				Slug:         opts.slug,
				Port:         opts.port,
				Dockerfile:   opts.dockerfile,
				Router:       opts.router,
				GHCROrg:      opts.ghcrOrg,
				DryRun:       opts.dryRun,
				GitopsRemote: opts.gitopsRemote,
			})
			if err != nil {
				return err
			}
			report.Print(cmd.OutOrStdout(), res)
			return nil
		},
	}

	f := cmd.Flags()
	f.StringVar(&opts.slug, "slug", "", "override the slug derived from the repo/dir name")
	f.IntVar(&opts.port, "port", 0, "container port override (0 = parse EXPOSE / default 3000)")
	f.StringVar(&opts.dockerfile, "dockerfile", "", "path to an existing Dockerfile for non-T3 detection")
	f.StringVar(&opts.router, "router", "", "T3 health-route location: app|pages (empty = auto-detect)")
	f.StringVar(&opts.ghcrOrg, "ghcr-org", "tkayage", "GHCR org for the image ghcr.io/<org>/<slug> (CI + manifests)")
	f.BoolVar(&opts.dryRun, "dry-run", false, "render app-repo files but skip the gitops publish/commit/push")
	f.StringVar(&opts.gitopsRemote, "gitops-remote", "", "override the gitops-homelab clone URL (empty = the real repo)")

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
