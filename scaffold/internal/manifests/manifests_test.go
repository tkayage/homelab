package manifests

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// t3Data is a representative T3 app: httpGet /api/health probes expected.
func t3Data() Data {
	return Data{
		Slug:         "myapp",
		GHCROrg:      "testorg",
		Port:         3000,
		IsT3:         true,
		PullUsername: "testorg",
		PullPassword: "dummy-token",
		PullAuthB64:  "dGVzdG9yZzpkdW1teS10b2tlbg==",
	}
}

// nonT3Data is a non-T3 app: tcpSocket probes expected.
func nonT3Data() Data {
	d := t3Data()
	d.Slug = "legacyapp"
	d.IsT3 = false
	d.Port = 8080
	return d
}

func mustRender(t *testing.T, data Data) string {
	t.Helper()
	dir := t.TempDir()
	if err := Render(dir, data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	return dir
}

func readFile(t *testing.T, dir, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(b)
}

// TestDeploymentT3 asserts the Deployment mirrors the edge-smoke shape with the
// CONTEXT divergences: name-only image (Pitfall 2), imagePullSecrets ghcr-pull,
// httpGet /api/health probes, bounded resources, and RollingUpdate.
func TestDeploymentT3(t *testing.T) {
	dir := mustRender(t, t3Data())
	dep := readFile(t, dir, "deployment.yaml")

	// Image is name-only: the tag is owned by the kustomization images:
	// transformer, so a ":tag" suffix here would defeat the CI bump (Pitfall 2).
	if !strings.Contains(dep, "image: ghcr.io/testorg/myapp\n") {
		t.Errorf("deployment missing name-only image ghcr.io/testorg/myapp:\n%s", dep)
	}
	if strings.Contains(dep, "image: ghcr.io/testorg/myapp:") {
		t.Error("deployment image carries a tag; the images: transformer owns the tag (Pitfall 2)")
	}
	for _, must := range []string{
		"app.kubernetes.io/name: myapp",
		"imagePullSecrets:",
		"name: ghcr-pull",
		"containerPort: 3000",
		"path: /api/health",
		"port: http",
		"cpu: 25m",
		"memory: 128Mi",
		"cpu: 500m",
		"memory: 512Mi",
		"type: RollingUpdate",
		"readinessProbe:",
		"livenessProbe:",
	} {
		if !strings.Contains(dep, must) {
			t.Errorf("deployment missing %q", must)
		}
	}
	// A T3 app must NOT use a tcpSocket probe.
	if strings.Contains(dep, "tcpSocket") {
		t.Error("T3 deployment should use httpGet probes, not tcpSocket")
	}
}

// TestDeploymentNonT3 asserts the non-T3 variant uses tcpSocket probes on the
// named port and never emits the /api/health httpGet path.
func TestDeploymentNonT3(t *testing.T) {
	dir := mustRender(t, nonT3Data())
	dep := readFile(t, dir, "deployment.yaml")

	if !strings.Contains(dep, "tcpSocket:") {
		t.Errorf("non-T3 deployment should use tcpSocket probes:\n%s", dep)
	}
	if strings.Contains(dep, "/api/health") {
		t.Error("non-T3 deployment should not reference the T3 /api/health route")
	}
	if !strings.Contains(dep, "containerPort: 8080") {
		t.Error("non-T3 deployment should honor the resolved port 8080")
	}
	// tcpSocket probes still resolve against the named http port.
	if !strings.Contains(dep, "port: http") {
		t.Error("non-T3 tcpSocket probe should target the named http port")
	}
}

// TestService asserts the Service mirrors edge-smoke: selector by slug label,
// port 80 -> targetPort http.
func TestService(t *testing.T) {
	dir := mustRender(t, t3Data())
	svc := readFile(t, dir, "service.yaml")
	for _, must := range []string{
		"kind: Service",
		"name: myapp",
		"app.kubernetes.io/name: myapp",
		"port: 80",
		"targetPort: http",
	} {
		if !strings.Contains(svc, must) {
			t.Errorf("service missing %q", must)
		}
	}
}

// TestIngress asserts the Ingress host is <slug>.app.kayage.co on ingressClassName
// traefik with a named http backend port.
func TestIngress(t *testing.T) {
	dir := mustRender(t, t3Data())
	ing := readFile(t, dir, "ingress.yaml")
	for _, must := range []string{
		"ingressClassName: traefik",
		"host: myapp.app.kayage.co",
		"pathType: Prefix",
		"name: http",
	} {
		if !strings.Contains(ing, must) {
			t.Errorf("ingress missing %q", must)
		}
	}
}

// imageFromLine extracts the value after a "<key>: " prefix on the unique line
// that carries it — used to compare the Deployment image and the kustomization
// images[].name byte-for-byte.
func imageFromLine(t *testing.T, body, keyPrefix string) string {
	t.Helper()
	for _, ln := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(ln)
		if strings.HasPrefix(trimmed, keyPrefix) {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, keyPrefix))
		}
	}
	t.Fatalf("no line with prefix %q in:\n%s", keyPrefix, body)
	return ""
}

// TestKustomizationSopsIndirection asserts the CRITICAL SOPS filename indirection
// (Pitfall 1): resources references the DECRYPTED pull-secret.yaml, never the
// on-disk pull-secret.enc.yaml. Verified live against gitops-smoke.
func TestKustomizationSopsIndirection(t *testing.T) {
	dir := mustRender(t, t3Data())
	kust := readFile(t, dir, "kustomization.yaml")

	if !strings.Contains(kust, "pull-secret.yaml") {
		t.Errorf("kustomization must reference the decrypted pull-secret.yaml:\n%s", kust)
	}
	if strings.Contains(kust, "pull-secret.enc.yaml") {
		t.Error("kustomization must NOT reference the encrypted pull-secret.enc.yaml (Pitfall 1)")
	}
	for _, must := range []string{"deployment.yaml", "service.yaml", "ingress.yaml", "newTag: latest"} {
		if !strings.Contains(kust, must) {
			t.Errorf("kustomization missing %q", must)
		}
	}
}

// TestImageNameMatch asserts the Deployment image and the kustomization
// images[].name are byte-identical (Pitfall 2) so the CI `kustomize edit set
// image` bump resolves instead of no-oping the pod onto :latest.
func TestImageNameMatch(t *testing.T) {
	dir := mustRender(t, t3Data())
	depImage := imageFromLine(t, readFile(t, dir, "deployment.yaml"), "image: ")
	kustName := imageFromLine(t, readFile(t, dir, "kustomization.yaml"), "- name: ")

	if depImage != kustName {
		t.Fatalf("image-name mismatch (Pitfall 2): deployment %q != kustomization %q", depImage, kustName)
	}
	if depImage != "ghcr.io/testorg/myapp" {
		t.Errorf("unexpected image string %q", depImage)
	}
}

// TestPullSecret asserts the rendered pull secret is a dockerconfigjson Secret
// named ghcr-pull carrying the ghcr.io auths body.
func TestPullSecret(t *testing.T) {
	dir := mustRender(t, t3Data())
	sec := readFile(t, dir, "pull-secret.yaml")
	for _, must := range []string{
		"kind: Secret",
		"name: ghcr-pull",
		"type: kubernetes.io/dockerconfigjson",
		".dockerconfigjson:",
		`"ghcr.io"`,
	} {
		if !strings.Contains(sec, must) {
			t.Errorf("pull-secret missing %q", must)
		}
	}
}

// TestKustomizeBuild proves the rendered manifest set is buildable by stock
// kustomize once the pull secret is in its decrypted (plaintext) state — which
// is exactly what Render writes. It shells out to `kustomize build`, asserts a
// clean exit, that the transformer pinned the image, and locks the full output
// to a golden fixture for regression.
func TestKustomizeBuild(t *testing.T) {
	kustomize, err := exec.LookPath("kustomize")
	if err != nil {
		t.Skip("kustomize not on PATH; skipping build proof")
	}
	dir := mustRender(t, t3Data())

	out, err := exec.Command(kustomize, "build", dir).CombinedOutput()
	if err != nil {
		t.Fatalf("kustomize build failed: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "image: ghcr.io/testorg/myapp:latest") {
		t.Errorf("kustomize build output did not pin the transformed image:\n%s", out)
	}

	want := readGolden(t, "apps-slug.golden.txt")
	if !bytes.Equal(out, want) {
		t.Fatalf("kustomize build output != golden:\n--- got ---\n%s\n--- want ---\n%s", out, want)
	}
}

func readGolden(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read golden %s: %v", name, err)
	}
	return b
}
