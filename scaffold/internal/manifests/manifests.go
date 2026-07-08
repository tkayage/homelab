// Package manifests renders the per-app GitOps manifest set the scaffolder
// commits to apps/<slug>/ in gitops-homelab: a Deployment, Service, Ingress,
// Kustomization, and a dockerconfigjson pull Secret. Every file is produced by
// rendering an embedded template through internal/templates (the shared
// text/template seam), parameterized by a single slug plus a handful of Data
// fields.
//
// Two load-bearing invariants (RESEARCH Pitfalls 1 & 2) hold this deploy path
// together and are asserted by the package tests:
//
//   - SOPS filename indirection: the on-disk secret is pull-secret.enc.yaml, but
//     kustomization.yaml references the DECRYPTED name pull-secret.yaml. The Argo
//     CMP decrypts *.enc.yaml -> *.yaml and removes the ciphertext before running
//     stock `kustomize build`, so referencing the encrypted name would fail
//     closed. Render writes the plaintext pull-secret.yaml; encryption + rename to
//     pull-secret.enc.yaml is plan 06-06's job.
//   - Image-name match: the Deployment `image:` and the kustomization
//     `images[].name` are byte-identical (ghcr.io/<org>/<slug>, tag owned by the
//     transformer) so the CI `kustomize edit set image` bump (06-04) resolves
//     instead of silently no-oping the pod onto :latest.
package manifests

import (
	"fmt"
	"path/filepath"

	"github.com/tkayage/homelab/scaffold/internal/templates"
)

// Data is the render context for the per-app gitops manifest set. A single slug
// drives the manifest names, labels, host, and image path; GHCROrg + Slug form
// the image string shared by the Deployment and the kustomization transformer.
type Data struct {
	// Slug is the app identifier: metadata name, app.kubernetes.io/name label,
	// ingress host prefix, and the trailing segment of the image path.
	Slug string
	// GHCROrg is the GHCR owner; the image is always ghcr.io/<GHCROrg>/<Slug>.
	GHCROrg string
	// Port is the container port the app listens on (Next.js default 3000).
	Port int
	// IsT3 selects the probe shape: T3 apps get httpGet /api/health probes,
	// non-T3 apps get tcpSocket probes on the same named port.
	IsT3 bool
	// PullUsername / PullPassword / PullAuthB64 fill the dockerconfigjson pull
	// secret. In this plan they carry dummy values in tests only; the real
	// read:packages token is operator-provided and encrypted in plan 06-06.
	PullUsername string
	PullPassword string
	PullAuthB64  string
}

// renderFiles maps each embedded gitops template to its output filename under
// the app dir. The kustomization + pull-secret entries are added in Task 2.
var renderFiles = []struct{ tmpl, out string }{
	{"gitops/deployment.yaml.tmpl", "deployment.yaml"},
	{"gitops/service.yaml.tmpl", "service.yaml"},
	{"gitops/ingress.yaml.tmpl", "ingress.yaml"},
}

// Render renders every gitops manifest template against data and writes the
// results into dir (typically apps/<slug>/). It does not create dir; the caller
// (the 06-07 orchestrator) is responsible for the directory.
func Render(dir string, data Data) error {
	for _, f := range renderFiles {
		dest := filepath.Join(dir, f.out)
		if err := templates.RenderToFile(f.tmpl, data, dest); err != nil {
			return fmt.Errorf("render %s: %w", f.out, err)
		}
	}
	return nil
}
