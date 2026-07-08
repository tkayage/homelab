package gitops

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// SOPS encryption constants for the per-app GHCR pull secret. These MUST match
// gitops/.sops.yaml so the emitted apps/<slug>/pull-secret.enc.yaml carries the
// same age recipient and encrypted_regex as the live gitops-smoke/secret.enc.yaml
// (which the ArgoCD sops-kustomize CMP decrypts at manifest-generation time).
const (
	// ageRecipient is the operator age public key from gitops/.sops.yaml. Only
	// the public recipient is needed to encrypt; the private key stays on the
	// dev box / in-cluster and is never referenced except for decryption.
	ageRecipient = "age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq"

	// encryptedRegex mirrors gitops/.sops.yaml: encrypt the whole stringData
	// (or data) block, leaving apiVersion/kind/metadata/type in cleartext.
	encryptedRegex = "^(data|stringData)$"

	// defaultAgeKeyFile is the operator age key used by sops for encrypt (and
	// decrypt). Overridable via SOPS_AGE_KEY_FILE / the internal helper for tests.
	defaultAgeKeyFile = "/home/tonny/.config/homelab/age/keys.txt"

	// plaintextSecretName is the decrypted pull-secret filename that
	// manifests.Render writes and the kustomization references (SOPS filename
	// indirection). It MUST NOT survive into a commit.
	plaintextSecretName = "pull-secret.yaml"

	// encSecretName is the SOPS ciphertext filename that alone may be committed
	// (matches gitops/.sops.yaml path_regex .*\.enc\.yaml$).
	encSecretName = "pull-secret.enc.yaml"
)

// EncryptPullSecret encrypts the rendered plaintext appDir/pull-secret.yaml into
// appDir/pull-secret.enc.yaml via `sops --encrypt`, then removes the plaintext so
// only the SOPS ciphertext remains on disk. It uses the operator age recipient
// from gitops/.sops.yaml and the operator age key at defaultAgeKeyFile.
//
// This is the security-critical hand-off from plan 06-05 (which renders the
// plaintext dockerconfigjson) to git: no plaintext credential may ever be staged
// (threat T-06-06). Callers should follow this with assertNoPlaintextSecret
// before `git add`.
func EncryptPullSecret(appDir string) error {
	return encryptPullSecretWith(appDir, ageRecipient, defaultAgeKeyFile)
}

// encryptPullSecretWith is the injectable core of EncryptPullSecret: recipient
// and ageKeyFile are explicit so tests can round-trip through a throwaway age
// keypair (threat T-06-17 — never touch the real operator key in tests).
//
// The age recipient and encrypted_regex are passed explicitly (not resolved from
// a .sops.yaml creation rule) so encryption is deterministic regardless of the
// working directory the scaffolder runs from, while still producing ciphertext
// byte-shape-compatible with the .sops.yaml rule.
func encryptPullSecretWith(appDir, recipient, ageKeyFile string) error {
	plaintext := filepath.Join(appDir, plaintextSecretName)
	if _, err := os.Stat(plaintext); err != nil {
		return fmt.Errorf("encrypt pull secret: plaintext %s not found: %w", plaintext, err)
	}

	if _, err := exec.LookPath("sops"); err != nil {
		return fmt.Errorf("encrypt pull secret: sops not on PATH (install per 06-01): %w", err)
	}

	encPath := filepath.Join(appDir, encSecretName)
	cmd := exec.Command("sops",
		"--encrypt",
		"--age", recipient,
		"--encrypted-regex", encryptedRegex,
		"--input-type", "yaml",
		"--output-type", "yaml",
		plaintext,
	)
	cmd.Env = append(os.Environ(), "SOPS_AGE_KEY_FILE="+ageKeyFile)
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("encrypt pull secret: sops --encrypt failed: %w: %s", err, sopsStderr(err))
	}

	// Write the ciphertext with restrictive perms, then remove the plaintext so
	// only the .enc.yaml (matching .*\.enc\.yaml$) is left for `git add`.
	if err := os.WriteFile(encPath, out, 0o600); err != nil {
		return fmt.Errorf("encrypt pull secret: write %s: %w", encPath, err)
	}
	if err := os.Remove(plaintext); err != nil {
		return fmt.Errorf("encrypt pull secret: remove plaintext %s: %w", plaintext, err)
	}
	return nil
}

// assertNoPlaintextSecret is the refuse-to-commit-plaintext guard (threat
// T-06-06). It fails if a plaintext pull-secret.yaml still exists in appDir — the
// only committable secret artifact is the SOPS ciphertext pull-secret.enc.yaml.
// Publish calls this immediately before `git add` so a plaintext dockerconfigjson
// can never be staged, even if encryption was skipped or partially failed.
func assertNoPlaintextSecret(appDir string) error {
	plaintext := filepath.Join(appDir, plaintextSecretName)
	if _, err := os.Stat(plaintext); err == nil {
		return fmt.Errorf("refusing to stage %s: plaintext pull secret present; only %s (SOPS ciphertext) may be committed (T-06-06)", plaintext, encSecretName)
	}
	// Defense in depth: if the .enc.yaml exists, verify it is actually SOPS
	// ciphertext (carries a sops: metadata block), not a mis-named plaintext.
	encPath := filepath.Join(appDir, encSecretName)
	if data, err := os.ReadFile(encPath); err == nil {
		if !looksEncrypted(data) {
			return fmt.Errorf("refusing to stage %s: not SOPS-encrypted (missing sops metadata / ENC[ markers) (T-06-06)", encPath)
		}
	}
	return nil
}

// looksEncrypted returns true when the bytes carry the SOPS ciphertext markers a
// correctly-encrypted secret must have: an ENC[ value and a sops: metadata block.
func looksEncrypted(data []byte) bool {
	s := string(data)
	return containsSub(s, "ENC[") && containsSub(s, "\nsops:")
}

func containsSub(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

// sopsStderr surfaces sops' stderr from an *exec.ExitError for actionable errors.
func sopsStderr(err error) string {
	if ee, ok := err.(*exec.ExitError); ok {
		return string(ee.Stderr)
	}
	return ""
}
