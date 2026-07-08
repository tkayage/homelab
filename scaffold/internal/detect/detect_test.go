package detect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestT3AppRouter(t *testing.T) {
	res, err := Detect("testdata/t3-app", 0, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Kind != T3 {
		t.Fatalf("Kind = %q; want T3", res.Kind)
	}
	if res.Router != RouterApp {
		t.Fatalf("Router = %q; want app", res.Router)
	}
	// T3 default port is 3000 unless overridden.
	if res.Port != 3000 {
		t.Fatalf("Port = %d; want 3000 (T3 default)", res.Port)
	}
}

func TestT3PagesRouter(t *testing.T) {
	res, err := Detect("testdata/t3-pages", 0, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Kind != T3 {
		t.Fatalf("Kind = %q; want T3", res.Kind)
	}
	if res.Router != RouterPages {
		t.Fatalf("Router = %q; want pages", res.Router)
	}
}

func TestNonT3OK(t *testing.T) {
	res, err := Detect("testdata/nont3-ok", 0, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Kind != NonT3 {
		t.Fatalf("Kind = %q; want NonT3", res.Kind)
	}
	if !res.HasDockerfile {
		t.Fatal("HasDockerfile = false; want true")
	}
	if res.Port != 8080 {
		t.Fatalf("Port = %d; want 8080 (parsed EXPOSE)", res.Port)
	}
	if len(res.Warnings) != 0 {
		t.Fatalf("Warnings = %v; want none (non-root USER present)", res.Warnings)
	}
}

func TestNonT3NoUser(t *testing.T) {
	res, err := Detect("testdata/nont3-nouser", 0, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Kind != NonT3 {
		t.Fatalf("Kind = %q; want NonT3", res.Kind)
	}
	if res.Port != 5000 {
		t.Fatalf("Port = %d; want 5000 (parsed EXPOSE)", res.Port)
	}
	if !hasWarningAbout(res.Warnings, "USER") {
		t.Fatalf("Warnings = %v; want a non-root USER recommendation", res.Warnings)
	}
}

func TestNonT3Missing(t *testing.T) {
	res, err := Detect("testdata/nont3-missing", 0, "")
	if err == nil {
		t.Fatal("expected error for missing Dockerfile (non-T3 must provide its own image config)")
	}
	if res.Kind != NonT3 {
		t.Fatalf("Kind = %q; want NonT3 even on the failure path", res.Kind)
	}
	if res.HasDockerfile {
		t.Fatal("HasDockerfile = true; want false")
	}
}

func TestPortOverride(t *testing.T) {
	// Override wins over a parsed EXPOSE.
	res, err := Detect("testdata/nont3-ok", 9999, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Port != 9999 {
		t.Fatalf("Port = %d; want 9999 (--port override beats EXPOSE)", res.Port)
	}
	// Override also wins for T3.
	res, err = Detect("testdata/t3-app", 4321, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Port != 4321 {
		t.Fatalf("T3 Port = %d; want 4321 (--port override)", res.Port)
	}
}

func TestDockerfilePathOverride(t *testing.T) {
	// An explicit --dockerfile path outside the repo root is honored.
	res, err := Detect("testdata/nont3-missing", 0, "testdata/nont3-ok/Dockerfile")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Kind != NonT3 || !res.HasDockerfile {
		t.Fatalf("expected NonT3 with Dockerfile via --dockerfile override; got Kind=%q HasDockerfile=%v", res.Kind, res.HasDockerfile)
	}
	if res.Port != 8080 {
		t.Fatalf("Port = %d; want 8080 parsed from the overridden Dockerfile", res.Port)
	}
}

// Detection must never mutate a Dockerfile it inspects (SCAF-06 hard rule).
func TestDetectNeverWritesDockerfile(t *testing.T) {
	paths := []string{"testdata/nont3-ok/Dockerfile", "testdata/nont3-nouser/Dockerfile"}
	before := map[string][]byte{}
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatalf("read %s: %v", p, err)
		}
		before[p] = b
	}
	if _, err := Detect("testdata/nont3-ok", 0, ""); err != nil {
		t.Fatalf("detect nont3-ok: %v", err)
	}
	if _, err := Detect("testdata/nont3-nouser", 0, ""); err != nil {
		t.Fatalf("detect nont3-nouser: %v", err)
	}
	for _, p := range paths {
		after, err := os.ReadFile(p)
		if err != nil {
			t.Fatalf("re-read %s: %v", p, err)
		}
		if string(after) != string(before[p]) {
			t.Fatalf("Detect mutated %s; SCAF-06 forbids overwriting an existing Dockerfile", p)
		}
	}
}

func hasWarningAbout(warnings []string, substr string) bool {
	for _, w := range warnings {
		if strings.Contains(w, substr) {
			return true
		}
	}
	return false
}

// guard against accidental absolute-path assumptions in fixtures
var _ = filepath.Join
