package report

import (
	"bytes"
	"strings"
	"testing"
)

// TestPrintT3 asserts the SCAF-05 report for a T3 app carries every required
// line: the generated app-repo files (Dockerfile + workflow + health route), the
// gitops commit + path, the expected URL, the Argo application name, and a
// health-check hint referencing the httpGet /api/health probe.
func TestPrintT3(t *testing.T) {
	r := Result{
		Slug: "myt3",
		IsT3: true,
		GeneratedFiles: []string{
			"Dockerfile",
			".github/workflows/deploy.yml",
			"app/api/health/route.ts",
		},
		GitopsCommit: "abc1234",
		GitopsPath:   "apps/myt3/",
		URL:          "https://myt3.app.kayage.co",
		ArgoApp:      "myt3",
		Port:         3000,
	}

	var buf bytes.Buffer
	Print(&buf, r)
	out := buf.String()

	for _, want := range []string{
		"Dockerfile",
		".github/workflows/deploy.yml",
		"app/api/health/route.ts",
		"abc1234",
		"apps/myt3/",
		"https://myt3.app.kayage.co",
		"myt3",
		"kubectl -n myt3 get deploy,pods",
		"/api/health",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("T3 report missing %q in:\n%s", want, out)
		}
	}
	// A T3 report must NOT claim it validated an existing Dockerfile.
	if strings.Contains(out, "validated existing Dockerfile") {
		t.Errorf("T3 report should not mention validating an existing Dockerfile:\n%s", out)
	}
}

// TestPrintNonT3 asserts the non-T3 report states the existing Dockerfile was
// validated (never overwritten), shows the TCP probe port, and still carries the
// URL, Argo app, and gitops commit.
func TestPrintNonT3(t *testing.T) {
	r := Result{
		Slug:                "svc",
		IsT3:                false,
		ValidatedDockerfile: true,
		GeneratedFiles: []string{
			".github/workflows/deploy.yml",
		},
		GitopsCommit: "def5678",
		GitopsPath:   "apps/svc/",
		URL:          "https://svc.app.kayage.co",
		ArgoApp:      "svc",
		Port:         8080,
		Warnings:     []string{"Dockerfile has no non-root USER directive"},
	}

	var buf bytes.Buffer
	Print(&buf, r)
	out := buf.String()

	for _, want := range []string{
		"validated existing Dockerfile",
		".github/workflows/deploy.yml",
		"def5678",
		"apps/svc/",
		"https://svc.app.kayage.co",
		"svc",
		"TCP probe on port 8080",
		"Dockerfile has no non-root USER directive",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("non-T3 report missing %q in:\n%s", want, out)
		}
	}
	// A non-T3 report must NOT reference the T3 health route.
	if strings.Contains(out, "/api/health") {
		t.Errorf("non-T3 report should not mention /api/health:\n%s", out)
	}
}

// TestPrintDryRun asserts a report with no gitops commit (a --dry-run run that
// skipped publishing) renders a clear "not published" note instead of a blank sha.
func TestPrintDryRun(t *testing.T) {
	r := Result{
		Slug:           "dry",
		IsT3:           true,
		GeneratedFiles: []string{"Dockerfile"},
		GitopsCommit:   "", // dry-run: nothing published
		GitopsPath:     "apps/dry/",
		URL:            "https://dry.app.kayage.co",
		ArgoApp:        "dry",
		Port:           3000,
	}

	var buf bytes.Buffer
	Print(&buf, r)
	out := buf.String()

	if !strings.Contains(out, "dry-run") {
		t.Errorf("dry-run report should note it was not published:\n%s", out)
	}
}
