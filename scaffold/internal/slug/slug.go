// Package slug derives and validates the single canonical identifier that drives
// every downstream artifact the scaffolder produces: image name (ghcr.io/tkayage/<slug>),
// namespace, ingress host (<slug>.app.kayage.co), and gitops dir (apps/<slug>).
//
// Validation here is a security control (threat T-06-07, slug/path injection): a slug is
// accepted only if it matches ^[a-z][a-z0-9-]{1,30}$, and rejection happens before any
// consumer writes a path or manifest. The package is intentionally side-effect free — no
// filesystem writes, no process execution.
package slug

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

// slugRe is the strict canonical form: a leading lowercase letter followed by 1..30
// additional lowercase-alphanumeric-or-hyphen characters (total length 2..31).
// Mirrors RESEARCH §7 / Security Domain V5. Kept as a package-level compiled regexp.
var slugRe = regexp.MustCompile(`^[a-z][a-z0-9-]{1,30}$`)

// nonSlugChars matches any character not permitted inside a slug body; used by Derive
// to coerce a directory basename into candidate slug form.
var nonSlugChars = regexp.MustCompile(`[^a-z0-9-]`)

// Validate returns nil when s is a well-formed slug and a descriptive error otherwise.
// It is the single injection guard: callers MUST run every operator-supplied --slug
// override and every Derive result through Validate before using the value in a path,
// image reference, or manifest.
func Validate(s string) error {
	if !slugRe.MatchString(s) {
		return fmt.Errorf("invalid slug %q: must match %s (start with a lowercase letter, "+
			"then 1-30 of [a-z0-9-], total length 2-31)", s, slugRe.String())
	}
	return nil
}

// Derive coerces the basename of dir into a canonical slug: lowercase, every character
// outside [a-z0-9-] replaced with '-', then leading/trailing '-' trimmed. If the coerced
// result does not satisfy Validate, Derive returns an empty string and an error instructing
// the operator to pass --slug explicitly — it never emits an invalid slug.
func Derive(dir string) (string, error) {
	base := strings.ToLower(filepath.Base(dir))
	base = nonSlugChars.ReplaceAllString(base, "-")
	base = strings.Trim(base, "-")
	if err := Validate(base); err != nil {
		return "", fmt.Errorf("cannot derive valid slug from %q; pass --slug", dir)
	}
	return base, nil
}
