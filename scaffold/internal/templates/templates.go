// Package templates bundles every scaffolder output template into the binary
// via //go:embed and renders them with text/template.
//
// This is the shared rendering seam every later plan builds on: plan 06-04 (CI
// workflow) and 06-05 (gitops manifests) add more .tmpl files under files/ and
// render them through the same Render helper. Template files MUST live under
// this package (files/), never a sibling directory — Go's //go:embed cannot
// reference a parent path (`..`).
//
// text/template is used deliberately (NOT html/template): the outputs are
// Dockerfiles and YAML, which html/template would corrupt by HTML-escaping.
// Every parse sets Option("missingkey=error") so referencing a field the data
// does not provide fails loudly instead of silently emitting "<no value>"
// (threat T-06-12 — a malformed generated file is worse than a loud failure).
package templates

import (
	"bytes"
	"embed"
	"fmt"
	"os"
	"text/template"
)

// files embeds every template under files/. The `all:` prefix is required so
// dotfiles (e.g. the seed files/.keep) are included in the embedded FS.
//
//go:embed all:files
var files embed.FS

// Render parses the named embedded template file and executes it against data,
// returning the rendered bytes.
//
// name is the path under files/, using forward slashes — e.g.
// "Dockerfile.t3.tmpl" or a nested "gitops/deployment.yaml.tmpl" that a later
// plan adds. An unknown name returns an error; a template that references a
// field absent from data returns an error (missingkey=error).
func Render(name string, data any) ([]byte, error) {
	content, err := files.ReadFile("files/" + name)
	if err != nil {
		return nil, fmt.Errorf("template %q not found: %w", name, err)
	}
	return render(name, content, data)
}

// render is the parse+execute core, split out from Render so the rendering
// contract (missingkey=error, no HTML escaping) can be unit-tested directly
// against inline template content without shipping a test fixture in the
// embedded FS.
func render(name string, content []byte, data any) ([]byte, error) {
	tmpl, err := template.New(name).Option("missingkey=error").Parse(string(content))
	if err != nil {
		return nil, fmt.Errorf("parse template %q: %w", name, err)
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return nil, fmt.Errorf("render template %q: %w", name, err)
	}
	return buf.Bytes(), nil
}

// RenderToFile renders name against data and writes the result to destPath with
// mode 0644. These are non-secret files (Dockerfile, workflow, k8s manifests);
// the SOPS-encrypted pull secret is generated and encrypted separately in plan
// 06-05, so 0600 is unnecessary here.
func RenderToFile(name string, data any, destPath string) error {
	out, err := Render(name, data)
	if err != nil {
		return err
	}
	if err := os.WriteFile(destPath, out, 0o644); err != nil {
		return fmt.Errorf("write %q: %w", destPath, err)
	}
	return nil
}
