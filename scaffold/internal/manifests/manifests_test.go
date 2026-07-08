package manifests

import (
	"os"
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
