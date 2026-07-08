package templates

import (
	"strings"
	"testing"
)

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
