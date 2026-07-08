package templates

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// workflowData is the render data for the generated deploy workflow template:
// the app slug and the GHCR org (default "tkayage", supplied by the scaffolder
// in 06-07). Both must be present or missingkey=error fails the render.
type workflowData struct {
	Slug    string
	GHCROrg string
}

// sampleWorkflowData renders the workflow the same way every test does so the
// golden and the structural assertions agree on one canonical rendering.
var sampleWorkflowData = workflowData{Slug: "myapp", GHCROrg: "tkayage"}

func renderWorkflow(t *testing.T) []byte {
	t.Helper()
	got, err := Render("workflow.deploy.yml.tmpl", sampleWorkflowData)
	if err != nil {
		t.Fatalf("Render(workflow.deploy.yml.tmpl): %v", err)
	}
	return got
}

// TestGoldenWorkflow locks the rendered two-job deploy workflow to its golden.
// The golden is the byte-for-byte contract every downstream plan (06-05
// manifests, 06-07 orchestrator) depends on; any drift in the workflow shape,
// the pinned action SHAs, or the image path is caught here.
func TestGoldenWorkflow(t *testing.T) {
	got := renderWorkflow(t)
	if want := readGolden(t, "workflow.golden"); !bytes.Equal(got, want) {
		t.Fatalf("workflow render != golden:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

// TestWorkflowActionlint renders the workflow and runs actionlint on it. This
// is the real validation gate for GITOPS-03/04 short of a live Actions run
// (deferred to Phase 8): actionlint parses the YAML, validates the schema,
// expression contexts (needs.build.outputs.short_sha, secrets, steps), and
// shellchecks every run: block.
func TestWorkflowActionlint(t *testing.T) {
	bin, err := exec.LookPath("actionlint")
	if err != nil {
		// actionlint is installed in 06-01; only skip if it is unexpectedly absent.
		t.Skip("actionlint not on PATH; skipping workflow lint")
	}

	got := renderWorkflow(t)
	// actionlint keys some checks off the .github/workflows/ path, so render into
	// that layout inside a temp dir.
	dir := t.TempDir()
	wfDir := filepath.Join(dir, ".github", "workflows")
	if err := os.MkdirAll(wfDir, 0o755); err != nil {
		t.Fatalf("mkdir workflows: %v", err)
	}
	wfPath := filepath.Join(wfDir, "deploy.yml")
	if err := os.WriteFile(wfPath, got, 0o644); err != nil {
		t.Fatalf("write rendered workflow: %v", err)
	}

	cmd := exec.Command(bin, wfPath)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("actionlint reported problems in the rendered workflow:\n%s", out)
	}
}

// TestWorkflowStructuralInvariants asserts the load-bearing security and
// correctness properties of the rendered workflow that the golden alone does
// not make explicit: the build→bump ordering, byte-identical short-SHA reuse
// (Pitfall 5), least-privilege permissions (T-06-02), and SHA-pinned actions
// (T-06-03).
func TestWorkflowStructuralInvariants(t *testing.T) {
	s := string(renderWorkflow(t))

	// Least privilege (T-06-02): only contents:read + packages:write.
	for _, must := range []string{"contents: read", "packages: write"} {
		if !strings.Contains(s, must) {
			t.Errorf("workflow missing least-privilege permission %q", must)
		}
	}
	if strings.Contains(s, "contents: write\n") {
		t.Error("top-level permissions grant contents: write — over-privileged (T-06-02)")
	}

	// Trigger on push to main, and a concurrency guard on the ref.
	for _, must := range []string{"on:", "branches: [main]", "concurrency:"} {
		if !strings.Contains(s, must) {
			t.Errorf("workflow missing %q", must)
		}
	}

	// build→bump ordering (Pitfall 4): the bump job needs the build job.
	if !strings.Contains(s, "needs: build") {
		t.Error("bump job does not declare `needs: build` — build→bump race (Pitfall 4)")
	}

	// The short SHA is computed once and exposed as a build-job output, then
	// reused byte-identically in the image tag and the gitops pin (Pitfall 5).
	if !strings.Contains(s, "short_sha: ${{ steps.vars.outputs.short_sha }}") {
		t.Error("build job does not expose short_sha as a job output")
	}
	if !strings.Contains(s, "short_sha=${GITHUB_SHA::7}") {
		t.Error("short_sha is not derived once from ${GITHUB_SHA::7}")
	}
	// Tag flow (build job) drives the pushed tag from the same computed string.
	if !strings.Contains(s, "type=raw,value=sha-${{ steps.vars.outputs.short_sha }}") {
		t.Error("image tag is not driven by the computed steps.vars.outputs.short_sha (Pitfall 5)")
	}
	// Kustomize edit (bump job) pins :sha-<short> using the reused job output.
	if !strings.Contains(s, "sha-${{ needs.build.outputs.short_sha }}") {
		t.Error("kustomize edit does not reuse needs.build.outputs.short_sha (Pitfall 5)")
	}
	// The SAME short_sha output is referenced by both the tag flow and the pin.
	if strings.Count(s, "outputs.short_sha }}") < 3 {
		t.Errorf("expected the short_sha output referenced in the tag flow and the kustomize edit; got %d references", strings.Count(s, "outputs.short_sha }}"))
	}

	// Image path is byte-identical between the build (metadata images:) and the
	// bump (kustomize edit set image key) — a mismatch no-ops the transformer
	// (Pitfall 2).
	if !strings.Contains(s, "images: ghcr.io/tkayage/myapp") {
		t.Error("build job image path is not ghcr.io/<org>/<slug>")
	}
	if !strings.Contains(s, "kustomize edit set image ghcr.io/tkayage/myapp=ghcr.io/tkayage/myapp:sha-") {
		t.Error("bump job image key does not match the build image path (Pitfall 2)")
	}

	// Cross-repo bump uses the least-privilege fine-grained PAT, never the GHCR
	// token (T-06-01); GHCR login uses the built-in GITHUB_TOKEN.
	if !strings.Contains(s, "repository: tkayage/gitops-homelab") {
		t.Error("bump job does not check out the gitops-homelab repo")
	}
	if !strings.Contains(s, "token: ${{ secrets.GITOPS_PUSH_TOKEN }}") {
		t.Error("bump job does not use the fine-grained GITOPS_PUSH_TOKEN (T-06-01)")
	}
	if !strings.Contains(s, "password: ${{ secrets.GITHUB_TOKEN }}") {
		t.Error("GHCR login does not use the built-in GITHUB_TOKEN")
	}

	// Rebase-retry loop guards two-writer contention on gitops main (Pitfall 6).
	if !strings.Contains(s, "git pull --rebase origin main") {
		t.Error("bump job push is missing the rebase-retry loop (Pitfall 6)")
	}

	// Every third-party action is pinned to a full 40-hex commit SHA, never a
	// floating @vN tag (T-06-03).
	usesRe := regexp.MustCompile(`(?m)uses:\s*(\S+)`)
	pinnedRe := regexp.MustCompile(`^[^@]+@[0-9a-f]{40}$`)
	matches := usesRe.FindAllStringSubmatch(s, -1)
	if len(matches) == 0 {
		t.Fatal("no `uses:` action references found in the workflow")
	}
	for _, m := range matches {
		ref := m[1]
		if !pinnedRe.MatchString(ref) {
			t.Errorf("action %q is not pinned to a full commit SHA (T-06-03)", ref)
		}
	}
}
