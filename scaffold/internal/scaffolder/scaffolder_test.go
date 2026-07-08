package scaffolder

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A dedicated throwaway age keypair for the offline gitops publish (threat
// T-06-17: never touch the operator key). Round-trips through sops 3.13.2. Shared
// with the gitops package's own test key so the encrypt path is exercised
// identically without importing test-only symbols across packages.
const (
	testAgeRecipient = "age168sywqplx2r3f6qm22yq90nv7duqrz42ka770lgd8pn0t0535syswqkldq"
	testAgeIdentity  = "AGE-SECRET-KEY-1R83EC9D2S6LGPPSFT4D5H2ALDT2VVJAVURC06MASUMDQ5P5MFJYSMX9EET"
)

func requireTool(t *testing.T, tool string) {
	t.Helper()
	if _, err := exec.LookPath(tool); err != nil {
		t.Skipf("%s not on PATH; skipping end-to-end scaffolder test", tool)
	}
}

// git runs git in dir and fails the test on error.
func gitT(t *testing.T, dir string, args ...string) {
	t.Helper()
	full := append([]string{"-C", dir}, args...)
	out, err := exec.Command("git", full...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
}

// gitOutT runs git in dir, returns trimmed stdout, fails on error.
func gitOutT(t *testing.T, dir string, args ...string) string {
	t.Helper()
	full := append([]string{"-C", dir}, args...)
	out, err := exec.Command("git", full...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

// initRepo creates a git repo at dir with the given files and an initial commit.
func initRepo(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for rel, content := range files {
		p := filepath.Join(dir, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", filepath.Dir(p), err)
		}
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatalf("write %s: %v", p, err)
		}
	}
	gitT(t, dir, "init", "-b", "main")
	gitT(t, dir, "config", "user.name", "Test")
	gitT(t, dir, "config", "user.email", "test@test.invalid")
	gitT(t, dir, "add", "-A")
	gitT(t, dir, "commit", "-m", "init")
}

// writeAgeKey writes the throwaway age identity into t.TempDir()/keys.txt.
func writeAgeKey(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "keys.txt")
	if err := os.WriteFile(p, []byte(testAgeIdentity+"\n"), 0o600); err != nil {
		t.Fatalf("write age key: %v", err)
	}
	return p
}

// setupGitops returns an Options fragment wired to an OFFLINE local bare gitops
// origin + a temp worktree + a dummy github.env + the throwaway age key.
func setupGitops(t *testing.T) Options {
	t.Helper()
	base := t.TempDir()
	origin := filepath.Join(base, "gitops-origin.git")
	gitT(t, base, "init", "--bare", "-b", "main", origin)

	githubEnv := filepath.Join(base, "github.env")
	if err := os.WriteFile(githubEnv, []byte("export GITHUB_TOKEN=dummy-local-token\n"), 0o600); err != nil {
		t.Fatalf("write github.env: %v", err)
	}
	return Options{
		GitopsRemote:   origin,
		GitopsWorktree: filepath.Join(base, ".local", "gitops-homelab"),
		GitHubEnv:      githubEnv,
		AgeRecipient:   testAgeRecipient,
		AgeKeyFile:     writeAgeKey(t),
		SkipPreflight:  true,
		PullUsername:   "tkayage",
		PullPassword:   "dummy-throwaway-token",
	}
}

// assertGitopsRegistered asserts apps/<slug>/ landed on the bare origin's main
// with the encrypted pull secret and NO plaintext (T-06-06).
func assertGitopsRegistered(t *testing.T, origin, slug string) {
	t.Helper()
	files := gitOutT(t, origin, "ls-tree", "-r", "--name-only", "main")
	for _, want := range []string{
		"apps/" + slug + "/deployment.yaml",
		"apps/" + slug + "/service.yaml",
		"apps/" + slug + "/ingress.yaml",
		"apps/" + slug + "/kustomization.yaml",
		"apps/" + slug + "/pull-secret.enc.yaml",
	} {
		if !strings.Contains(files, want) {
			t.Errorf("origin main missing %s\ntree:\n%s", want, files)
		}
	}
	if strings.Contains(files, "apps/"+slug+"/pull-secret.yaml") {
		t.Fatalf("plaintext pull-secret.yaml was committed to origin:\n%s", files)
	}
	enc := gitOutT(t, origin, "show", "main:apps/"+slug+"/pull-secret.enc.yaml")
	if !strings.Contains(enc, "ENC[") || !strings.Contains(enc, "sops:") {
		t.Errorf("committed pull-secret.enc.yaml is not SOPS ciphertext:\n%s", enc)
	}
	if strings.Contains(enc, "dummy-throwaway-token") {
		t.Fatalf("plaintext token leaked into committed ciphertext:\n%s", enc)
	}
}

// TestRunT3EndToEnd scaffolds a T3 fixture repo end-to-end against a local gitops
// origin: it must generate the Dockerfile, the App Router health route, and the
// deploy workflow in the app repo, register apps/<slug>/ in the origin with the
// encrypted pull secret, and return a Result carrying the URL + argo app name.
func TestRunT3EndToEnd(t *testing.T) {
	requireTool(t, "git")
	requireTool(t, "sops")
	requireTool(t, "kustomize")

	appDir := t.TempDir()
	initRepo(t, appDir, map[string]string{
		"package.json":   `{"name":"myt3","dependencies":{"next":"14.0.0"}}`,
		"next.config.js": "module.exports = { output: 'standalone' };\n",
		"app/page.tsx":   "export default function Page(){return null}\n",
	})

	opts := setupGitops(t)
	opts.Dir = appDir
	opts.Slug = "myt3"

	res, err := Run(opts)
	if err != nil {
		t.Fatalf("Run (T3): %v", err)
	}

	// App-repo files exist.
	for _, rel := range []string{"Dockerfile", ".github/workflows/deploy.yml", "app/api/health/route.ts"} {
		if _, statErr := os.Stat(filepath.Join(appDir, rel)); statErr != nil {
			t.Errorf("expected generated file %s: %v", rel, statErr)
		}
	}
	// The generated Dockerfile is a real T3 standalone build (digest-pinned base).
	df, _ := os.ReadFile(filepath.Join(appDir, "Dockerfile"))
	if !strings.Contains(string(df), "standalone") {
		t.Errorf("generated Dockerfile is not the T3 standalone build:\n%s", df)
	}
	// The workflow image org threads from the single GHCROrg source.
	wf, _ := os.ReadFile(filepath.Join(appDir, ".github/workflows/deploy.yml"))
	if !strings.Contains(string(wf), "ghcr.io/tkayage/myt3") {
		t.Errorf("workflow missing expected image ghcr.io/tkayage/myt3:\n%s", wf)
	}

	// GitOps registered with the encrypted secret.
	assertGitopsRegistered(t, opts.GitopsRemote, "myt3")

	// Result carries SCAF-05 fields.
	if res.URL != "https://myt3.app.kayage.co" {
		t.Errorf("URL = %q, want https://myt3.app.kayage.co", res.URL)
	}
	if res.ArgoApp != "myt3" {
		t.Errorf("ArgoApp = %q, want myt3", res.ArgoApp)
	}
	if !res.IsT3 {
		t.Errorf("IsT3 = false, want true")
	}
	if res.GitopsCommit == "" {
		t.Errorf("GitopsCommit empty; a non-dry-run publish must report the pushed sha")
	}
}

// TestRunNonT3EndToEnd scaffolds a non-T3 fixture (its own Dockerfile) end-to-end:
// the existing Dockerfile must be left byte-unchanged (SCAF-06 / T-06-18), only the
// workflow is generated in the app repo, and apps/<slug>/ is still registered.
func TestRunNonT3EndToEnd(t *testing.T) {
	requireTool(t, "git")
	requireTool(t, "sops")
	requireTool(t, "kustomize")

	dockerfile := "FROM alpine:3.20\nEXPOSE 8080\nUSER app\nCMD [\"/app\"]\n"
	appDir := t.TempDir()
	initRepo(t, appDir, map[string]string{
		"Dockerfile": dockerfile,
		"main.go":    "package main\nfunc main(){}\n",
	})

	before, err := os.ReadFile(filepath.Join(appDir, "Dockerfile"))
	if err != nil {
		t.Fatalf("read fixture Dockerfile: %v", err)
	}

	opts := setupGitops(t)
	opts.Dir = appDir
	opts.Slug = "svc"

	res, err := Run(opts)
	if err != nil {
		t.Fatalf("Run (non-T3): %v", err)
	}

	// The existing Dockerfile must be byte-unchanged (never overwritten).
	after, err := os.ReadFile(filepath.Join(appDir, "Dockerfile"))
	if err != nil {
		t.Fatalf("read Dockerfile after Run: %v", err)
	}
	if string(before) != string(after) {
		t.Fatalf("non-T3 Dockerfile was modified:\nbefore:\n%s\nafter:\n%s", before, after)
	}

	// Only the workflow is generated in the app repo (no health route, no new Dockerfile).
	if _, statErr := os.Stat(filepath.Join(appDir, ".github/workflows/deploy.yml")); statErr != nil {
		t.Errorf("expected generated workflow: %v", statErr)
	}
	if _, statErr := os.Stat(filepath.Join(appDir, "app/api/health/route.ts")); statErr == nil {
		t.Errorf("non-T3 must not generate a T3 health route")
	}

	// GitOps registered with the encrypted secret.
	assertGitopsRegistered(t, opts.GitopsRemote, "svc")

	// Result reflects non-T3, carries the resolved EXPOSE port and validated flag.
	if res.IsT3 {
		t.Errorf("IsT3 = true, want false")
	}
	if !res.ValidatedDockerfile {
		t.Errorf("ValidatedDockerfile = false, want true for non-T3")
	}
	if res.Port != 8080 {
		t.Errorf("Port = %d, want 8080 (parsed EXPOSE)", res.Port)
	}
	if res.URL != "https://svc.app.kayage.co" || res.ArgoApp != "svc" {
		t.Errorf("Result URL/ArgoApp = %q/%q, want svc", res.URL, res.ArgoApp)
	}
}

// TestRunDryRunSkipsPublish asserts --dry-run renders the app-repo files but does
// NOT touch the gitops origin, and reports an empty commit.
func TestRunDryRunSkipsPublish(t *testing.T) {
	requireTool(t, "git")
	requireTool(t, "sops")
	requireTool(t, "kustomize")

	appDir := t.TempDir()
	initRepo(t, appDir, map[string]string{
		"package.json":   `{"name":"dry","dependencies":{"next":"14.0.0"}}`,
		"next.config.js": "module.exports = { output: 'standalone' };\n",
		"app/page.tsx":   "export default function Page(){return null}\n",
	})

	opts := setupGitops(t)
	opts.Dir = appDir
	opts.Slug = "dry"
	opts.DryRun = true

	res, err := Run(opts)
	if err != nil {
		t.Fatalf("Run (dry-run): %v", err)
	}
	if _, statErr := os.Stat(filepath.Join(appDir, "Dockerfile")); statErr != nil {
		t.Errorf("dry-run still generates app-repo files: %v", statErr)
	}
	// Nothing pushed: the bare origin's main ref must not exist (unborn branch).
	if err := exec.Command("git", "-C", opts.GitopsRemote, "show-ref", "--verify", "--quiet", "refs/heads/main").Run(); err == nil {
		t.Errorf("dry-run must not publish to the gitops origin (refs/heads/main exists)")
	}
	if res.GitopsCommit != "" {
		t.Errorf("dry-run GitopsCommit = %q, want empty", res.GitopsCommit)
	}
}
