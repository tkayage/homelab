package gitops

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tkayage/homelab/scaffold/internal/manifests"
)

// runGitT is a test helper that runs git in dir and fails the test on error.
func runGitT(t *testing.T, dir string, args ...string) string {
	t.Helper()
	full := append([]string{"-C", dir}, args...)
	out, err := exec.Command("git", full...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return string(out)
}

// TestGitPublishToLocalBareOrigin runs the full Publish flow OFFLINE against a
// local bare repository standing in for gitops-homelab: it clones/syncs a
// worktree, renders apps/<slug>/, SOPS-encrypts the pull secret, commits, and
// pushes to the bare origin's main — then asserts the commit landed with the
// encrypted (not plaintext) manifests present. No network, preflight stubbed.
func TestGitPublishToLocalBareOrigin(t *testing.T) {
	requireGit(t)
	requireSops(t)

	base := t.TempDir()

	// A local bare repo as the fake origin, initialized with a main branch.
	origin := filepath.Join(base, "origin.git")
	runGitT(t, base, "init", "--bare", "-b", "main", origin)

	worktree := filepath.Join(base, ".local", "gitops-homelab")

	// A temp github.env with a dummy token (never used for a local file remote,
	// but loadCredentials requires it) — mirrors ~/.config/homelab/github.env.
	githubEnv := filepath.Join(base, "github.env")
	if err := os.WriteFile(githubEnv, []byte("export GITHUB_TOKEN=dummy-local-token\n"), 0o600); err != nil {
		t.Fatalf("write github.env: %v", err)
	}
	ageKey := writeTestAgeKey(t)

	cfg := Config{
		RepoURL:       origin,
		Worktree:      worktree,
		GitHubEnv:     githubEnv,
		AgeRecipient:  testAgeRecipient,
		AgeKeyFile:    ageKey,
		SkipPreflight: true, // no GitHub API for a local bare origin
	}
	data := manifests.Data{
		Slug:         "myapp",
		GHCROrg:      "tkayage",
		Port:         3000,
		IsT3:         true,
		PullUsername: "tkayage",
		PullPassword: "dummy-throwaway-token",
		PullAuthB64:  "dGtheWFnZTpkdW1teS10aHJvd2F3YXktdG9rZW4=",
	}

	if err := Publish(cfg, "myapp", data); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	// The push must have landed apps/myapp/ on the bare origin's main.
	files := runGitT(t, origin, "ls-tree", "-r", "--name-only", "main")
	for _, want := range []string{
		"apps/myapp/deployment.yaml",
		"apps/myapp/service.yaml",
		"apps/myapp/ingress.yaml",
		"apps/myapp/kustomization.yaml",
		"apps/myapp/pull-secret.enc.yaml",
	} {
		if !strings.Contains(files, want) {
			t.Errorf("origin main missing %s\ntree:\n%s", want, files)
		}
	}
	// The plaintext pull-secret.yaml must NEVER reach the origin (T-06-06).
	if strings.Contains(files, "apps/myapp/pull-secret.yaml") {
		t.Fatalf("plaintext pull-secret.yaml was committed to origin:\n%s", files)
	}
	// The commit message is the registration message.
	msg := runGitT(t, origin, "log", "-1", "--pretty=%s", "main")
	if strings.TrimSpace(msg) != "deploy(myapp): register app" {
		t.Errorf("unexpected commit subject: %q", strings.TrimSpace(msg))
	}
	// The committed ciphertext must be SOPS-encrypted (no plaintext token).
	enc := runGitT(t, origin, "show", "main:apps/myapp/pull-secret.enc.yaml")
	if !strings.Contains(enc, "ENC[") || !strings.Contains(enc, "sops:") {
		t.Errorf("committed pull-secret.enc.yaml is not SOPS ciphertext:\n%s", enc)
	}
	if strings.Contains(enc, "dummy-throwaway-token") {
		t.Fatalf("plaintext token leaked into committed ciphertext:\n%s", enc)
	}
}

// TestGitPublishReSync proves a second Publish against an already-populated
// origin exercises the fetch/reset re-sync path (not a fresh clone) and advances
// history by exactly one commit — no spurious or empty commits.
func TestGitPublishReSync(t *testing.T) {
	requireGit(t)
	requireSops(t)

	base := t.TempDir()
	origin := filepath.Join(base, "origin.git")
	runGitT(t, base, "init", "--bare", "-b", "main", origin)
	worktree := filepath.Join(base, ".local", "gitops-homelab")
	githubEnv := filepath.Join(base, "github.env")
	if err := os.WriteFile(githubEnv, []byte("GITHUB_TOKEN=dummy\n"), 0o600); err != nil {
		t.Fatalf("write github.env: %v", err)
	}
	ageKey := writeTestAgeKey(t)

	cfg := Config{
		RepoURL:       origin,
		Worktree:      worktree,
		GitHubEnv:     githubEnv,
		AgeRecipient:  testAgeRecipient,
		AgeKeyFile:    ageKey,
		SkipPreflight: true,
	}
	data := manifests.Data{Slug: "again", GHCROrg: "tkayage", Port: 3000, IsT3: false,
		PullUsername: "tkayage", PullPassword: "dummy-throwaway-token", PullAuthB64: "eA=="}

	if err := Publish(cfg, "again", data); err != nil {
		t.Fatalf("first Publish: %v", err)
	}
	countBefore := strings.TrimSpace(runGitT(t, origin, "rev-list", "--count", "main"))

	// Second publish: SOPS re-encryption produces a fresh IV so the ciphertext
	// differs each run; a real second commit is therefore expected and fine. We
	// only assert Publish succeeds and history advances by exactly one, i.e. no
	// spurious extra commits.
	if err := Publish(cfg, "again", data); err != nil {
		t.Fatalf("second Publish: %v", err)
	}
	countAfter := strings.TrimSpace(runGitT(t, origin, "rev-list", "--count", "main"))
	// A fresh SOPS IV per run means the ciphertext differs, so the re-sync path
	// produces exactly one new commit — never zero (would mean the push was lost)
	// and never more than one (would mean spurious commits).
	if countBefore != "1" || countAfter != "2" {
		t.Fatalf("re-sync commit count: before=%s after=%s; want before=1 after=2", countBefore, countAfter)
	}
}

func requireGit(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not on PATH; skipping gitops integration test")
	}
}
