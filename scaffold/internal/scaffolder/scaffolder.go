// Package scaffolder is the orchestrator that composes every wave-2..4 package
// into the single `scaffold` command (SCAF-01). Run performs the RESEARCH
// "System Architecture" steps end-to-end:
//
//  1. preflight        — git, sops, kustomize resolve on PATH
//  2. resolve repo root — git rev-parse --show-toplevel (+ origin remote, report-only)
//  3. slug             — slug.Derive(root) or validate the --slug override
//  4. detect           — detect.Detect for Kind / Router / Port / Warnings
//  5. render app files  — T3: Dockerfile + health route + deploy workflow;
//     non-T3: validate (never overwrite) the Dockerfile + workflow
//  6. gitops.Publish    — render + SOPS-encrypt + commit apps/<slug>/ to gitops-homelab
//  7. report.Result     — SCAF-05 completion report data
//
// The GHCR org is threaded from a SINGLE source (Options.GHCROrg, default
// "tkayage") into BOTH the deploy workflow image name (via templates) AND the
// gitops Deployment image + kustomization images newName (via manifests.Data), so
// the image path ghcr.io/<org>/<slug> is byte-identical across CI and manifests
// (resolves assumption A2; prevents the Pitfall-2 image-name mismatch).
package scaffolder

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/tkayage/homelab/scaffold/internal/detect"
	"github.com/tkayage/homelab/scaffold/internal/gitops"
	"github.com/tkayage/homelab/scaffold/internal/manifests"
	"github.com/tkayage/homelab/scaffold/internal/report"
	"github.com/tkayage/homelab/scaffold/internal/slug"
	"github.com/tkayage/homelab/scaffold/internal/templates"
)

// defaultGHCROrg is the single centralized GHCR org (A2). It is the default for
// Options.GHCROrg and is threaded identically into the workflow image and the
// gitops manifests so ghcr.io/<org>/<slug> never diverges between CI and deploy.
const defaultGHCROrg = "tkayage"

// defaultGitopsWorktree mirrors gitops.defaultWorktree (that constant is
// unexported). Run resolves the worktree explicitly so it can read the pushed
// gitops commit sha back for the SCAF-05 report.
const defaultGitopsWorktree = ".local/gitops-homelab"

// requiredTools are the external binaries Run shells out to. Preflight asserts
// they resolve on PATH before any file is written (matches the 06-01 skeleton).
var requiredTools = []string{"git", "sops", "kustomize"}

// Options carries every input to Run. The CLI (cmd/scaffold) fills Dir/Slug/Port/
// Dockerfile/Router/GHCROrg/DryRun/GitopsRemote from flags; the remaining fields
// are test/integration seams (default to the operator values when zero) so the
// end-to-end test can run OFFLINE against a local bare gitops repo with a
// throwaway age keypair and a dummy token.
type Options struct {
	// Dir is the app repo working directory (default "."). Run resolves the repo
	// root from it via git rev-parse --show-toplevel.
	Dir string
	// Slug overrides the slug derived from the repo/dir name (empty = derive).
	Slug string
	// Port overrides the container port (0 = parsed EXPOSE / default 3000).
	Port int
	// Dockerfile points non-T3 detection at a Dockerfile outside the repo root.
	Dockerfile string
	// Router overrides the T3 health-route location: "app" | "pages" (empty = auto).
	Router string
	// GHCROrg is the SINGLE source of the GHCR org (default "tkayage"). Threaded
	// into both the workflow image and the gitops manifests.
	GHCROrg string
	// DryRun renders the app-repo files but skips gitops.Publish (no clone,
	// encrypt, commit, or push). The report notes nothing was published.
	DryRun bool
	// Public opts the generated app into public Cloudflare/AWS-edge exposure.
	// False means LAN-only through the Phase 4 wildcard local edge.
	Public bool

	// GitopsRemote overrides the gitops-homelab clone URL (a local bare repo in
	// the offline test; empty = the real https://github.com/<org>/gitops-homelab).
	GitopsRemote string
	// GitopsWorktree overrides the local clone target (empty = .local/gitops-homelab).
	GitopsWorktree string
	// GitHubEnv overrides the github.env credential file (test seam).
	GitHubEnv string
	// PullTokenFile points at a file containing the real classic read:packages
	// GHCR pull token. This is the operator-safe non-argv credential path.
	PullTokenFile string
	// AgeRecipient / AgeKeyFile override the SOPS encrypt identity (test seam).
	AgeRecipient string
	AgeKeyFile   string
	// SkipPreflight bypasses the GitHub push-permission check (set for a local
	// bare origin with no GitHub API).
	SkipPreflight bool

	// PullUsername / PullPassword are the private-GHCR read:packages credential
	// baked into the dockerconfigjson pull secret. PullPassword is retained only
	// as a hidden offline test seam; real tokens should come from PullTokenFile or
	// GHCR_PULL_TOKEN so they never appear in argv/process listings.
	PullUsername string
	PullPassword string
}

// Run executes the full scaffold and returns the SCAF-05 report data. It is the
// single entrypoint the cobra RunE calls; every side effect (file writes, the
// gitops commit) happens here.
func Run(opts Options) (report.Result, error) {
	var res report.Result

	// (1) preflight — required tools on PATH.
	if err := preflight(requiredTools); err != nil {
		return res, err
	}

	// (2) resolve the app repo root and (report-only) its origin remote.
	dir := opts.Dir
	if dir == "" {
		dir = "."
	}
	root, err := gitOut(dir, "rev-parse", "--show-toplevel")
	if err != nil {
		return res, fmt.Errorf("scaffold: %s is not a git repository (run scaffold inside an app repo): %w", dir, err)
	}
	root = strings.TrimSpace(root)
	// The origin remote is read for reporting/logging only; A2 keeps the image path
	// slug-canonical, so a repo with NO remote is NOT an error (the read is
	// intentionally best-effort and its result is discarded).
	_, _ = gitOut(root, "config", "--get", "remote.origin.url")

	// (3) slug — derive or validate the override.
	appSlug := opts.Slug
	if appSlug == "" {
		appSlug, err = slug.Derive(root)
		if err != nil {
			return res, fmt.Errorf("scaffold: %w", err)
		}
	} else if err := slug.Validate(appSlug); err != nil {
		return res, fmt.Errorf("scaffold: %w", err)
	}

	// (4) detect T3/non-T3 + router + port + warnings.
	det, err := detect.Detect(root, opts.Port, opts.Dockerfile)
	if err != nil {
		return res, fmt.Errorf("scaffold: %w", err)
	}

	ghcrOrg := opts.GHCROrg
	if ghcrOrg == "" {
		ghcrOrg = defaultGHCROrg
	}
	pullPassword, err := resolvePullPassword(opts)
	if err != nil {
		return res, err
	}
	opts.PullPassword = pullPassword

	warnings := append([]string(nil), det.Warnings...)

	// (5) render app-repo files.
	var generated []string
	isT3 := det.Kind == detect.T3
	if isT3 {
		gen, w, rerr := renderT3(root, det, opts.Router, ghcrOrg, appSlug)
		if rerr != nil {
			return res, rerr
		}
		generated = gen
		warnings = append(warnings, w...)
	} else {
		gen, rerr := renderNonT3(root, ghcrOrg, appSlug)
		if rerr != nil {
			return res, rerr
		}
		generated = gen
	}

	// (6) gitops.Publish — render + encrypt + commit apps/<slug>/ (unless dry-run).
	gitopsCommit := ""
	if !opts.DryRun {
		commit, perr := publishGitops(opts, appSlug, ghcrOrg, det.Port, isT3)
		if perr != nil {
			return res, perr
		}
		gitopsCommit = commit
	}

	// (7) assemble the SCAF-05 report.
	res = report.Result{
		Slug:                appSlug,
		IsT3:                isT3,
		GeneratedFiles:      generated,
		ValidatedDockerfile: !isT3,
		GitopsCommit:        gitopsCommit,
		GitopsPath:          fmt.Sprintf("apps/%s/", appSlug),
		URL:                 fmt.Sprintf("https://%s.app.kayage.co", appSlug),
		ArgoApp:             appSlug,
		Port:                det.Port,
		Warnings:            warnings,
	}
	return res, nil
}

// renderT3 writes the T3 Dockerfile, the router-correct health route, and the
// deploy workflow into the app repo, returning the generated file paths (relative
// to root) and any warnings (e.g. a missing next.config output:'standalone').
func renderT3(root string, det detect.Result, routerOverride, ghcrOrg, appSlug string) (generated []string, warnings []string, err error) {
	// Dockerfile (T3 standalone build), parameterized by the resolved port.
	if err = templates.RenderToFile("Dockerfile.t3.tmpl", struct{ Port int }{det.Port}, filepath.Join(root, "Dockerfile")); err != nil {
		return nil, nil, fmt.Errorf("scaffold: render Dockerfile: %w", err)
	}
	generated = append(generated, "Dockerfile")

	// Health route at the router-correct path.
	router := det.Router
	switch routerOverride {
	case "app":
		router = detect.RouterApp
	case "pages":
		router = detect.RouterPages
	case "":
		// keep detected router
	default:
		return nil, nil, fmt.Errorf("scaffold: invalid --router %q (want app|pages)", routerOverride)
	}

	var routeTmpl, routeRel string
	if router == detect.RouterPages {
		routeTmpl, routeRel = "health.page.ts.tmpl", filepath.Join("pages", "api", "health.ts")
	} else {
		routeTmpl, routeRel = "health.route.ts.tmpl", filepath.Join("app", "api", "health", "route.ts")
	}
	routeDest := filepath.Join(root, routeRel)
	if err = os.MkdirAll(filepath.Dir(routeDest), 0o755); err != nil {
		return nil, nil, fmt.Errorf("scaffold: create health route dir: %w", err)
	}
	// Health templates are static (no fields); render with nil data.
	if err = templates.RenderToFile(routeTmpl, nil, routeDest); err != nil {
		return nil, nil, fmt.Errorf("scaffold: render health route: %w", err)
	}
	generated = append(generated, filepath.ToSlash(routeRel))

	// next.config must set output:'standalone' for the standalone Docker build; if
	// we cannot confirm it, warn (RESEARCH: the scaffolder asserts or instructs).
	warnings = append(warnings, standaloneWarnings(root)...)

	// Deploy workflow.
	wf, err := renderWorkflow(root, ghcrOrg, appSlug)
	if err != nil {
		return nil, nil, err
	}
	generated = append(generated, wf)

	return generated, warnings, nil
}

// renderNonT3 validates (never overwrites) the existing Dockerfile — detection
// already confirmed it — and writes only the deploy workflow.
func renderNonT3(root, ghcrOrg, appSlug string) (generated []string, err error) {
	wf, err := renderWorkflow(root, ghcrOrg, appSlug)
	if err != nil {
		return nil, err
	}
	return []string{wf}, nil
}

// renderWorkflow writes .github/workflows/deploy.yml and returns its relative
// path. GHCROrg + Slug flow into the workflow image name (byte-identical to the
// gitops manifests' image via the shared ghcrOrg source).
func renderWorkflow(root, ghcrOrg, appSlug string) (string, error) {
	rel := filepath.Join(".github", "workflows", "deploy.yml")
	dest := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return "", fmt.Errorf("scaffold: create workflow dir: %w", err)
	}
	data := struct{ GHCROrg, Slug string }{ghcrOrg, appSlug}
	if err := templates.RenderToFile("workflow.deploy.yml.tmpl", data, dest); err != nil {
		return "", fmt.Errorf("scaffold: render workflow: %w", err)
	}
	return filepath.ToSlash(rel), nil
}

// standaloneWarnings returns a warning if no next.config with output:'standalone'
// can be confirmed at root (empty slice if it is present).
func standaloneWarnings(root string) []string {
	for _, name := range []string{"next.config.js", "next.config.mjs", "next.config.ts", "next.config.cjs"} {
		raw, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			continue
		}
		if strings.Contains(string(raw), "standalone") {
			return nil
		}
		return []string{fmt.Sprintf("%s does not set output:'standalone'; the T3 Dockerfile needs it — add `output: 'standalone'` to your next.config", name)}
	}
	return []string{"no next.config found; add one with `output: 'standalone'` so the T3 Dockerfile's standalone build works"}
}

// publishGitops renders + encrypts + commits apps/<slug>/ into gitops-homelab and
// returns the short commit sha at the worktree HEAD (for the report). The GHCR org
// threads into manifests.Data so the Deployment image + kustomization newName match
// the workflow image byte-for-byte.
func publishGitops(opts Options, appSlug, ghcrOrg string, port int, isT3 bool) (string, error) {
	worktree := opts.GitopsWorktree
	if worktree == "" {
		worktree = defaultGitopsWorktree
	}

	pullUser := opts.PullUsername
	if pullUser == "" {
		pullUser = ghcrOrg
	}
	authB64 := base64.StdEncoding.EncodeToString([]byte(pullUser + ":" + opts.PullPassword))

	data := manifests.Data{
		Slug:         appSlug,
		GHCROrg:      ghcrOrg,
		Port:         port,
		IsT3:         isT3,
		Public:       opts.Public,
		PullUsername: pullUser,
		PullPassword: opts.PullPassword,
		PullAuthB64:  authB64,
	}
	cfg := gitops.Config{
		RepoURL:       opts.GitopsRemote,
		Worktree:      worktree,
		GitHubEnv:     opts.GitHubEnv,
		AgeRecipient:  opts.AgeRecipient,
		AgeKeyFile:    opts.AgeKeyFile,
		SkipPreflight: opts.SkipPreflight,
	}
	if err := gitops.Publish(cfg, appSlug, data); err != nil {
		return "", fmt.Errorf("scaffold: gitops publish: %w", err)
	}

	commit, err := gitOut(worktree, "rev-parse", "--short", "HEAD")
	if err != nil {
		// The push succeeded; not being able to read the sha back is non-fatal.
		return "", nil
	}
	return strings.TrimSpace(commit), nil
}

func resolvePullPassword(opts Options) (string, error) {
	if opts.DryRun {
		return "", nil
	}
	if opts.PullTokenFile != "" {
		raw, err := os.ReadFile(opts.PullTokenFile)
		if err != nil {
			return "", fmt.Errorf("scaffold: read --pull-token-file: %w", err)
		}
		token := strings.TrimSpace(string(raw))
		if token == "" {
			return "", fmt.Errorf("scaffold: --pull-token-file is empty; provide a GHCR read:packages token")
		}
		return token, nil
	}
	if token := strings.TrimSpace(os.Getenv("GHCR_PULL_TOKEN")); token != "" {
		return token, nil
	}
	if opts.PullPassword != "" {
		if !isDummyPullPassword(opts.PullPassword) {
			return "", fmt.Errorf("scaffold: --pull-password is an offline dummy-token seam; provide real GHCR credentials via --pull-token-file or GHCR_PULL_TOKEN")
		}
		return opts.PullPassword, nil
	}
	return "", fmt.Errorf("scaffold: missing GHCR pull token; provide a classic read:packages token via --pull-token-file or GHCR_PULL_TOKEN")
}

func isDummyPullPassword(token string) bool {
	token = strings.ToLower(strings.TrimSpace(token))
	return strings.Contains(token, "dummy") || strings.Contains(token, "throwaway") || strings.Contains(token, "test")
}

// preflight asserts every required external tool resolves on PATH, returning an
// error naming the first missing one. No side effects.
func preflight(tools []string) error {
	for _, tool := range tools {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("missing required command %q on PATH (install it before running scaffold)", tool)
		}
	}
	return nil
}

// gitOut runs `git -C dir <args>` and returns stdout, surfacing stderr on failure.
func gitOut(dir string, args ...string) (string, error) {
	full := append([]string{"-C", dir}, args...)
	cmd := exec.Command("git", full...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, msg)
		}
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return stdout.String(), nil
}
