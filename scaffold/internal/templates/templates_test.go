package templates

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// dockerfileData is the render data for the T3 Dockerfile template.
type dockerfileData struct{ Port int }

func readGolden(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read golden %s: %v", name, err)
	}
	return b
}

// TestGoldenDockerfileT3 locks the rendered T3 Dockerfile to its golden and
// asserts the security-relevant properties: multi-stage standalone build,
// digest-pinned base image (threat T-06-04), HOSTNAME=0.0.0.0, and a non-root
// uid 1001 runtime user (threat T-06-11).
func TestGoldenDockerfileT3(t *testing.T) {
	got, err := Render("Dockerfile.t3.tmpl", dockerfileData{Port: 3000})
	if err != nil {
		t.Fatalf("Render(Dockerfile.t3.tmpl): %v", err)
	}
	if want := readGolden(t, "dockerfile.golden"); !bytes.Equal(got, want) {
		t.Fatalf("Dockerfile render != golden:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}

	s := string(got)
	for _, must := range []string{
		"@sha256:", "AS deps", "AS builder", "AS runner",
		"HOSTNAME=0.0.0.0", "--uid 1001", "USER nextjs",
		"standalone", "EXPOSE 3000", `CMD ["node", "server.js"]`,
	} {
		if !strings.Contains(s, must) {
			t.Errorf("rendered Dockerfile missing %q", must)
		}
	}
	// A floating base tag (no digest) is the threat T-06-04 anti-pattern.
	if strings.Contains(s, "FROM node:22-alpine\n") || strings.Contains(s, "FROM node:22-alpine ") {
		t.Error("base image uses a floating tag, not a digest pin")
	}
}

// TestGoldenDockerfilePortParam proves the container port is parameterized: a
// non-default port flows into both ENV PORT and EXPOSE.
func TestGoldenDockerfilePortParam(t *testing.T) {
	got, err := Render("Dockerfile.t3.tmpl", dockerfileData{Port: 8080})
	if err != nil {
		t.Fatalf("Render(Dockerfile.t3.tmpl, 8080): %v", err)
	}
	s := string(got)
	if !strings.Contains(s, "PORT=8080") || !strings.Contains(s, "EXPOSE 8080") {
		t.Errorf("port 8080 not propagated to ENV PORT / EXPOSE:\n%s", s)
	}
}

// TestGoldenHealthRouteApp locks the App Router health handler to its golden
// and asserts it returns HTTP 200.
func TestGoldenHealthRouteApp(t *testing.T) {
	got, err := Render("health.route.ts.tmpl", nil)
	if err != nil {
		t.Fatalf("Render(health.route.ts.tmpl): %v", err)
	}
	if want := readGolden(t, "health.route.golden"); !bytes.Equal(got, want) {
		t.Fatalf("health route render != golden:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	if !strings.Contains(string(got), "200") {
		t.Error("App Router health handler does not return status 200")
	}
}

// TestGoldenHealthPagePages locks the Pages Router health handler to its golden
// and asserts it returns HTTP 200.
func TestGoldenHealthPagePages(t *testing.T) {
	got, err := Render("health.page.ts.tmpl", nil)
	if err != nil {
		t.Fatalf("Render(health.page.ts.tmpl): %v", err)
	}
	if want := readGolden(t, "health.page.golden"); !bytes.Equal(got, want) {
		t.Fatalf("health page render != golden:\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	if !strings.Contains(string(got), "200") {
		t.Error("Pages Router health handler does not return status 200")
	}
}

// TestRenderResolvesEmbeddedFile proves Render loads a file out of the embedded
// FS. The seed files/.keep is empty, so a successful render yields empty output
// and no error — enough to prove the embed pattern matched and ReadFile works.
func TestRenderResolvesEmbeddedFile(t *testing.T) {
	out, err := Render(".keep", nil)
	if err != nil {
		t.Fatalf("Render(.keep) unexpected error: %v", err)
	}
	if len(out) != 0 {
		t.Fatalf("Render(.keep) = %q, want empty", out)
	}
}

// TestRenderUnknownNameErrors proves an unknown template name is a loud error,
// not an empty render.
func TestRenderUnknownNameErrors(t *testing.T) {
	if _, err := Render("does-not-exist.tmpl", nil); err == nil {
		t.Fatal("Render(unknown) = nil error, want an error")
	}
}

// TestRenderMissingKeyErrors exercises the parse+execute core with inline
// template content (data is inline; the template need not be embedded). It
// proves Option("missingkey=error") is wired: a referenced field absent from
// the data map fails loudly instead of emitting "<no value>".
func TestRenderMissingKeyErrors(t *testing.T) {
	// Present key renders.
	out, err := render("greeting", []byte("hello {{.Name}}"), map[string]any{"Name": "world"})
	if err != nil {
		t.Fatalf("render with present key: unexpected error: %v", err)
	}
	if got := string(out); got != "hello world" {
		t.Fatalf("render = %q, want %q", got, "hello world")
	}

	// Missing key errors (must NOT emit "<no value>").
	got, err := render("greeting", []byte("hello {{.Name}}"), map[string]any{})
	if err == nil {
		t.Fatalf("render with missing key = %q, want an error", got)
	}
	if strings.Contains(string(got), "<no value>") {
		t.Fatalf("render emitted %q — missingkey=error not in effect", got)
	}
}
