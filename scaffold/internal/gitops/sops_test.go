package gitops

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Throwaway age keypair used ONLY by the SOPS round-trip tests. age-keygen is not
// on PATH in this environment, so this is a fixed, dedicated throwaway pair
// (verified to round-trip through sops 3.13.2). It is NOT the operator key at
// ~/.config/homelab/age/keys.txt — threat T-06-17 requires tests never touch the
// real key. Regenerate with: age-keygen (or ecdh X25519 + bech32) if rotated.
const (
	testAgeRecipient = "age168sywqplx2r3f6qm22yq90nv7duqrz42ka770lgd8pn0t0535syswqkldq"
	testAgeIdentity  = "AGE-SECRET-KEY-1R83EC9D2S6LGPPSFT4D5H2ALDT2VVJAVURC06MASUMDQ5P5MFJYSMX9EET"
)

// sampleDockerConfigJSON is the plaintext dockerconfigjson body the pull secret
// carries; the round-trip must recover it byte-for-byte after decrypt.
const sampleDockerConfigJSON = `{"auths":{"ghcr.io":{"username":"tkayage","password":"dummy-throwaway-token","auth":"dGtheWFnZTpkdW1teS10aHJvd2F3YXktdG9rZW4="}}}`

func writeSamplePullSecret(t *testing.T, appDir string) {
	t.Helper()
	if err := os.MkdirAll(appDir, 0o755); err != nil {
		t.Fatalf("mkdir appDir: %v", err)
	}
	body := "apiVersion: v1\n" +
		"kind: Secret\n" +
		"metadata:\n" +
		"  name: ghcr-pull\n" +
		"type: kubernetes.io/dockerconfigjson\n" +
		"stringData:\n" +
		"  .dockerconfigjson: |\n" +
		"    " + sampleDockerConfigJSON + "\n"
	if err := os.WriteFile(filepath.Join(appDir, plaintextSecretName), []byte(body), 0o600); err != nil {
		t.Fatalf("write plaintext pull secret: %v", err)
	}
}

// writeTestAgeKey writes the throwaway age identity into t.TempDir()/keys.txt and
// returns the path, mirroring the operator's ~/.config/homelab/age/keys.txt.
func writeTestAgeKey(t *testing.T) string {
	t.Helper()
	keyFile := filepath.Join(t.TempDir(), "keys.txt")
	if err := os.WriteFile(keyFile, []byte(testAgeIdentity+"\n"), 0o600); err != nil {
		t.Fatalf("write age key: %v", err)
	}
	return keyFile
}

func requireSops(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("sops"); err != nil {
		t.Skip("sops not on PATH (installed in 06-01); skipping SOPS round-trip")
	}
}

// TestSopsEncryptRoundTrip proves EncryptPullSecret produces a SOPS ciphertext
// (sops: metadata + ENC[ value), deletes the plaintext, and that decrypting with
// the throwaway key recovers the original dockerconfigjson exactly.
func TestSopsEncryptRoundTrip(t *testing.T) {
	requireSops(t)
	appDir := filepath.Join(t.TempDir(), "apps", "myapp")
	writeSamplePullSecret(t, appDir)
	keyFile := writeTestAgeKey(t)

	if err := encryptPullSecretWith(appDir, testAgeRecipient, keyFile); err != nil {
		t.Fatalf("encryptPullSecretWith: %v", err)
	}

	// Plaintext must be gone; only the ciphertext may remain.
	if _, err := os.Stat(filepath.Join(appDir, plaintextSecretName)); !os.IsNotExist(err) {
		t.Fatalf("plaintext %s still present after encryption (err=%v)", plaintextSecretName, err)
	}
	encPath := filepath.Join(appDir, encSecretName)
	enc, err := os.ReadFile(encPath)
	if err != nil {
		t.Fatalf("read ciphertext: %v", err)
	}
	encStr := string(enc)
	if !strings.Contains(encStr, "ENC[") {
		t.Errorf("ciphertext missing ENC[ marker:\n%s", encStr)
	}
	if !strings.Contains(encStr, "\nsops:") {
		t.Errorf("ciphertext missing sops: metadata block:\n%s", encStr)
	}
	if !strings.Contains(encStr, "recipient: "+testAgeRecipient) {
		t.Errorf("ciphertext missing expected age recipient %s:\n%s", testAgeRecipient, encStr)
	}
	if !strings.Contains(encStr, "encrypted_regex: ^(data|stringData)$") {
		t.Errorf("ciphertext missing expected encrypted_regex:\n%s", encStr)
	}
	// The plaintext token must NOT appear in the ciphertext.
	if strings.Contains(encStr, "dummy-throwaway-token") {
		t.Fatalf("plaintext token leaked into ciphertext:\n%s", encStr)
	}

	// Decrypt with the throwaway key and assert the dockerconfigjson round-trips.
	cmd := exec.Command("sops", "-d", encPath)
	cmd.Env = append(os.Environ(), "SOPS_AGE_KEY_FILE="+keyFile)
	dec, err := cmd.Output()
	if err != nil {
		stderr := ""
		if ee, ok := err.(*exec.ExitError); ok {
			stderr = string(ee.Stderr)
		}
		t.Fatalf("sops -d failed: %v: %s", err, stderr)
	}
	if !strings.Contains(string(dec), sampleDockerConfigJSON) {
		t.Fatalf("round-trip did not recover dockerconfigjson.\ngot:\n%s\nwant substring:\n%s", dec, sampleDockerConfigJSON)
	}
}

// TestSopsAssertNoPlaintextGuard exercises the refuse-to-commit-plaintext guard
// (T-06-06) directly: it fails while a plaintext pull-secret.yaml exists, passes
// once only the ciphertext remains, and rejects a mis-named plaintext .enc.yaml.
func TestSopsAssertNoPlaintextGuard(t *testing.T) {
	requireSops(t)
	appDir := filepath.Join(t.TempDir(), "apps", "guard")
	writeSamplePullSecret(t, appDir)

	// Plaintext present -> guard must refuse.
	if err := assertNoPlaintextSecret(appDir); err == nil {
		t.Fatalf("guard passed while plaintext %s present; expected refusal", plaintextSecretName)
	}

	// Encrypt, then the guard must pass (plaintext removed, ciphertext valid).
	keyFile := writeTestAgeKey(t)
	if err := encryptPullSecretWith(appDir, testAgeRecipient, keyFile); err != nil {
		t.Fatalf("encryptPullSecretWith: %v", err)
	}
	if err := assertNoPlaintextSecret(appDir); err != nil {
		t.Fatalf("guard refused after encryption: %v", err)
	}

	// A mis-named plaintext masquerading as .enc.yaml must be rejected.
	badDir := filepath.Join(t.TempDir(), "apps", "bad")
	if err := os.MkdirAll(badDir, 0o755); err != nil {
		t.Fatalf("mkdir badDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(badDir, encSecretName), []byte("stringData:\n  token: plaintext\n"), 0o600); err != nil {
		t.Fatalf("write mis-named enc: %v", err)
	}
	if err := assertNoPlaintextSecret(badDir); err == nil {
		t.Fatalf("guard accepted a non-encrypted %s; expected refusal", encSecretName)
	}
}
