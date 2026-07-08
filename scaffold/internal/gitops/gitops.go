// Package gitops performs the scaffolder's single write into external state: it
// clones/refreshes the gitops-homelab repository, renders apps/<slug>/ into the
// worktree (via internal/manifests), SOPS-encrypts the per-app GHCR pull secret,
// and commits+pushes to main — the initial GitOps registration that Argo's
// ApplicationSet auto-adopts (no per-app Argo change).
//
// It is a faithful Go port of scripts/gitops-platform.sh (load_credentials,
// sync_worktree, publish, and the push-permission preflight), shelling out to the
// system `git` binary with the exact x-access-token + GITHUB_TOKEN askpass
// convention rather than adopting go-git (RESEARCH §1). Two guardrails hold this
// path safe:
//
//   - Push preflight (T-06-16): before any write, assert the credential actually
//     has push on gitops-homelab (GitHub API permissions.push).
//   - Refuse-to-commit-plaintext (T-06-06): the rendered pull-secret.yaml is
//     SOPS-encrypted to pull-secret.enc.yaml and the plaintext is removed +
//     asserted-absent before `git add`, so a plaintext dockerconfigjson can never
//     be staged.
package gitops

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/tkayage/homelab/scaffold/internal/manifests"
)

// Default constants mirror scripts/gitops-platform.sh so the scaffolder's initial
// commit reuses the same repo, worktree, and credential locations.
const (
	defaultOrg       = "tkayage"
	defaultRepoName  = "gitops-homelab"
	defaultWorktree  = ".local/gitops-homelab"
	defaultGitHubEnv = "/home/tonny/.config/homelab/github.env"
	defaultUserName  = "Homelab GitOps Operator"
	defaultUserEmail = "gitops@homelab.invalid"
)

// Config parameterizes Publish. Every external dependency (repo URL, worktree
// path, credential file, age recipient/key, preflight) is overridable so the
// offline integration test can point at a LOCAL bare repo and a throwaway age
// keypair with no network access.
type Config struct {
	// Org is the GitHub owner of gitops-homelab (default "tkayage"). Used to
	// build the API URL for the push preflight.
	Org string
	// RepoName is the gitops repository name (default "gitops-homelab").
	RepoName string
	// RepoURL is the clone URL. Defaults to https://github.com/<Org>/<RepoName>.git;
	// tests set it to a local bare repo (file path) to run offline.
	RepoURL string
	// Worktree is the local clone target (default ".local/gitops-homelab").
	Worktree string
	// GitHubEnv is the shell env file providing GITHUB_TOKEN
	// (default "/home/tonny/.config/homelab/github.env").
	GitHubEnv string
	// AgeRecipient / AgeKeyFile drive SOPS encryption of the pull secret. They
	// default to the operator values (ageRecipient / defaultAgeKeyFile); tests
	// inject a throwaway pair.
	AgeRecipient string
	AgeKeyFile   string
	// UserName / UserEmail are set on the worktree for the commit identity.
	UserName  string
	UserEmail string
	// SkipPreflight disables the GitHub push-permission check. Set true when
	// RepoURL points at a local bare repo (no GitHub API to query) so the
	// integration test runs fully offline.
	SkipPreflight bool
}

func (c *Config) withDefaults() {
	if c.Org == "" {
		c.Org = defaultOrg
	}
	if c.RepoName == "" {
		c.RepoName = defaultRepoName
	}
	if c.RepoURL == "" {
		c.RepoURL = fmt.Sprintf("https://github.com/%s/%s.git", c.Org, c.RepoName)
	}
	if c.Worktree == "" {
		c.Worktree = defaultWorktree
	}
	if c.GitHubEnv == "" {
		c.GitHubEnv = defaultGitHubEnv
	}
	if c.AgeRecipient == "" {
		c.AgeRecipient = ageRecipient
	}
	if c.AgeKeyFile == "" {
		c.AgeKeyFile = defaultAgeKeyFile
	}
	if c.UserName == "" {
		c.UserName = defaultUserName
	}
	if c.UserEmail == "" {
		c.UserEmail = defaultUserEmail
	}
}

// Publish is the scaffolder's registration entrypoint: it loads the operator
// credential, preflights push permission, syncs the gitops-homelab worktree,
// renders apps/<slug>/, SOPS-encrypts the pull secret (refusing to stage any
// plaintext), then commits "deploy(<slug>): register app" and pushes origin main.
// It is a no-op (no commit) when the rendered manifests are byte-identical to
// what is already committed.
func Publish(cfg Config, slug string, data manifests.Data) error {
	cfg.withDefaults()

	token, env, err := loadCredentials(&cfg)
	if err != nil {
		return err
	}

	// T-06-16: prove the credential can push BEFORE writing anything.
	if !cfg.SkipPreflight {
		if err := preflightPush(cfg, token); err != nil {
			return err
		}
	}

	if err := syncWorktree(cfg, env); err != nil {
		return err
	}

	appDir := filepath.Join(cfg.Worktree, "apps", slug)
	if err := os.MkdirAll(appDir, 0o755); err != nil {
		return fmt.Errorf("publish: create app dir %s: %w", appDir, err)
	}
	if err := manifests.Render(appDir, data); err != nil {
		return fmt.Errorf("publish: render manifests: %w", err)
	}

	// T-06-06: encrypt the rendered plaintext pull secret and hard-assert no
	// plaintext survives before staging.
	if err := encryptPullSecretWith(appDir, cfg.AgeRecipient, cfg.AgeKeyFile); err != nil {
		return fmt.Errorf("publish: %w", err)
	}
	if err := assertNoPlaintextSecret(appDir); err != nil {
		return fmt.Errorf("publish: %w", err)
	}

	// Stage only apps/<slug> and commit+push if there is a change.
	if err := git(cfg, env, "add", filepath.Join("apps", slug)); err != nil {
		return fmt.Errorf("publish: git add: %w", err)
	}
	if staged, err := hasStagedChanges(cfg, env); err != nil {
		return err
	} else if !staged {
		return nil // already registered; nothing to commit
	}
	if err := git(cfg, env, "commit", "-m", fmt.Sprintf("deploy(%s): register app", slug)); err != nil {
		return fmt.Errorf("publish: git commit: %w", err)
	}
	if err := git(cfg, env, "push", "origin", "main"); err != nil {
		return fmt.Errorf("publish: git push: %w", err)
	}
	return nil
}

// loadCredentials reads GITHUB_TOKEN from cfg.GitHubEnv, writes a mode-0700
// git-askpass.sh that answers Username with x-access-token and Password with the
// token (mirroring gitops-platform.sh lines 19-37), and returns the token plus
// the exec environment (GIT_USERNAME / GIT_PASSWORD / GIT_ASKPASS /
// GIT_TERMINAL_PROMPT=0) to run git under.
func loadCredentials(cfg *Config) (token string, env []string, err error) {
	token, err = readGithubToken(cfg.GitHubEnv)
	if err != nil {
		return "", nil, err
	}

	// The askpass script lives beside the worktree (.local/), matching the shell
	// convention ($ROOT/.local/git-askpass.sh).
	localDir := filepath.Dir(cfg.Worktree)
	if err := os.MkdirAll(localDir, 0o755); err != nil {
		return "", nil, fmt.Errorf("credentials: mkdir %s: %w", localDir, err)
	}
	askpass := filepath.Join(localDir, "git-askpass.sh")
	script := "#!/bin/sh\n" +
		"case \"$1\" in\n" +
		"  *Username*) printf '%s\\n' \"$GIT_USERNAME\" ;;\n" +
		"  *) printf '%s\\n' \"$GIT_PASSWORD\" ;;\n" +
		"esac\n"
	if err := os.WriteFile(askpass, []byte(script), 0o700); err != nil {
		return "", nil, fmt.Errorf("credentials: write askpass: %w", err)
	}

	env = append(os.Environ(),
		"GIT_USERNAME=x-access-token",
		"GIT_PASSWORD="+token,
		"GIT_ASKPASS="+askpass,
		"GIT_TERMINAL_PROMPT=0",
	)
	return token, env, nil
}

// readGithubToken parses a shell-style env file (KEY=VALUE, optional `export`,
// optional quotes, `#` comments) and returns GITHUB_TOKEN, erroring if the file
// is unreadable or the token is absent/empty.
func readGithubToken(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("credentials: missing GitHub credentials %s: %w", path, err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		key, val, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(key) != "GITHUB_TOKEN" {
			continue
		}
		val = strings.TrimSpace(val)
		val = strings.Trim(val, `"'`)
		if val == "" {
			return "", fmt.Errorf("credentials: GITHUB_TOKEN is empty in %s", path)
		}
		return val, nil
	}
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("credentials: read %s: %w", path, err)
	}
	return "", fmt.Errorf("credentials: GITHUB_TOKEN not set in %s", path)
}

// preflightPush asserts the credential has push permission on <org>/<repo> via
// the GitHub API before any write (gitops-platform.sh lines 46-49).
func preflightPush(cfg Config, token string) error {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s", cfg.Org, cfg.RepoName)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("preflight: build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("preflight: GitHub API request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("preflight: GitHub API returned %s for %s", resp.Status, url)
	}

	var body struct {
		Permissions struct {
			Push bool `json:"push"`
		} `json:"permissions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return fmt.Errorf("preflight: decode API response: %w", err)
	}
	if !body.Permissions.Push {
		return fmt.Errorf("preflight: credential cannot push to %s/%s", cfg.Org, cfg.RepoName)
	}
	return nil
}

// syncWorktree clones cfg.RepoURL into cfg.Worktree when absent (initializing the
// main branch), else fetches origin main and hard-resets to it, then sets the
// commit identity on the worktree (gitops-platform.sh lines 70-84).
func syncWorktree(cfg Config, env []string) error {
	if _, err := os.Stat(filepath.Join(cfg.Worktree, ".git")); err != nil {
		if err := os.RemoveAll(cfg.Worktree); err != nil {
			return fmt.Errorf("sync: clean worktree: %w", err)
		}
		if err := runGit(env, "", "clone", cfg.RepoURL, cfg.Worktree); err != nil {
			return fmt.Errorf("sync: clone %s: %w", cfg.RepoURL, err)
		}
		// Ensure we are on main (handles a freshly-initialized empty origin whose
		// main branch is unborn as well as a populated repo).
		_ = git(cfg, env, "checkout", "-B", "main")
	} else {
		if err := git(cfg, env, "fetch", "origin", "main"); err != nil {
			return fmt.Errorf("sync: fetch origin main: %w", err)
		}
		if err := git(cfg, env, "checkout", "-B", "main"); err != nil {
			return fmt.Errorf("sync: checkout main: %w", err)
		}
		if err := git(cfg, env, "reset", "--hard", "origin/main"); err != nil {
			return fmt.Errorf("sync: reset --hard origin/main: %w", err)
		}
	}
	if err := git(cfg, env, "config", "user.name", cfg.UserName); err != nil {
		return fmt.Errorf("sync: set user.name: %w", err)
	}
	if err := git(cfg, env, "config", "user.email", cfg.UserEmail); err != nil {
		return fmt.Errorf("sync: set user.email: %w", err)
	}
	return nil
}

// hasStagedChanges reports whether the worktree index differs from HEAD
// (equivalent to the shell `! git diff --cached --quiet`).
func hasStagedChanges(cfg Config, env []string) (bool, error) {
	err := runGit(env, cfg.Worktree, "diff", "--cached", "--quiet")
	if err == nil {
		return false, nil // exit 0 => no staged changes
	}
	// `git diff --cached --quiet` exits 1 when the index differs from HEAD; that
	// is the "changes present" signal, not an error.
	if exitErr := unwrapExit(err); exitErr != nil && exitErr.ExitCode() == 1 {
		return true, nil
	}
	return false, fmt.Errorf("diff --cached: %w", err)
}

// unwrapExit returns the *exec.ExitError in err's chain, or nil.
func unwrapExit(err error) *exec.ExitError {
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return ee
	}
	return nil
}

// git runs a git subcommand inside cfg.Worktree with the credential env.
func git(cfg Config, env []string, args ...string) error {
	return runGit(env, cfg.Worktree, args...)
}

// runGit executes git with -C dir (when dir != "") under env, surfacing stderr on
// failure. GIT_TERMINAL_PROMPT=0 in env prevents any interactive credential hang.
func runGit(env []string, dir string, args ...string) error {
	full := args
	if dir != "" {
		full = append([]string{"-C", dir}, args...)
	}
	cmd := exec.Command("git", full...)
	if env != nil {
		cmd.Env = env
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, msg)
		}
		return fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return nil
}
