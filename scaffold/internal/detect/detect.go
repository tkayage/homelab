// Package detect classifies an app repository as a T3/Next.js project or a generic
// (non-T3) container project, and — for non-T3 — inspects the operator's existing
// Dockerfile without ever mutating it.
//
// Detection is strictly read-only (threat T-06-09): it parses package.json and Dockerfile
// on disk and never writes or overwrites any file. SCAF-06 is a hard rule — an existing
// non-T3 Dockerfile is validated and warned about, never regenerated.
package detect

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Kind is the project classification.
type Kind string

const (
	// T3 is a Next.js project (package.json declares a "next" dependency).
	T3 Kind = "T3"
	// NonT3 is any other containerizable project; it must supply its own Dockerfile.
	NonT3 Kind = "NonT3"
)

// Router is the Next.js router style, meaningful only for T3 projects. It decides where
// the generated health route lands (app/api/health/route.ts vs pages/api/health.ts).
type Router string

const (
	// RouterApp is the App Router (app/ directory present).
	RouterApp Router = "app"
	// RouterPages is the Pages Router (pages/ directory, no app/).
	RouterPages Router = "pages"
)

// defaultPort is the fallback container port when neither --port nor an EXPOSE line
// resolves a value (matches the CONTEXT default of 3000).
const defaultPort = 3000

// Result carries the outcome of detection. For T3, Router is set and Port defaults to
// 3000 (unless overridden). For non-T3, Port is parsed from the Dockerfile's first EXPOSE
// (unless overridden) and Warnings may include a non-root USER recommendation.
type Result struct {
	Kind          Kind
	Router        Router // set only for T3
	Port          int
	HasDockerfile bool
	Warnings      []string
}

// Detect classifies the project rooted at dir.
//
// portOverride, when > 0, wins over any parsed or absent EXPOSE port. dockerfilePath, when
// non-empty, points detection at a Dockerfile outside dir's root (the --dockerfile flag).
//
// A T3 project is one whose package.json declares "next" in dependencies or devDependencies.
// A non-T3 project must have a Dockerfile (at dir root or dockerfilePath); if none exists,
// Detect returns a NonT3 Result with HasDockerfile=false AND a non-nil error so the caller
// can fail with a clear message (SCAF-06: non-T3 must provide its own image config).
//
// Detect never writes to, creates, or mutates any file.
func Detect(dir string, portOverride int, dockerfilePath string) (Result, error) {
	if isT3(dir) {
		return Result{
			Kind:   T3,
			Router: detectRouter(dir),
			Port:   resolvePort(portOverride, 0),
		}, nil
	}
	return detectNonT3(dir, portOverride, dockerfilePath)
}

// isT3 reports whether dir/package.json parses and declares a "next" dependency in either
// dependencies or devDependencies.
func isT3(dir string) bool {
	raw, err := os.ReadFile(filepath.Join(dir, "package.json"))
	if err != nil {
		return false
	}
	var pkg struct {
		Dependencies    map[string]string `json:"dependencies"`
		DevDependencies map[string]string `json:"devDependencies"`
	}
	if err := json.Unmarshal(raw, &pkg); err != nil {
		return false
	}
	if _, ok := pkg.Dependencies["next"]; ok {
		return true
	}
	_, ok := pkg.DevDependencies["next"]
	return ok
}

// detectRouter resolves the Next.js router style: app/ present -> app, else pages/ -> pages,
// else default to app (Assumption A5).
func detectRouter(dir string) Router {
	if isDir(filepath.Join(dir, "app")) {
		return RouterApp
	}
	if isDir(filepath.Join(dir, "pages")) {
		return RouterPages
	}
	return RouterApp
}

func isDir(p string) bool {
	info, err := os.Stat(p)
	return err == nil && info.IsDir()
}

// detectNonT3 locates and inspects the Dockerfile for a non-T3 project. It is read-only.
func detectNonT3(dir string, portOverride int, dockerfilePath string) (Result, error) {
	res := Result{Kind: NonT3}

	path := dockerfilePath
	if path == "" {
		path = filepath.Join(dir, "Dockerfile")
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		// No Dockerfile: still classify NonT3, but surface a clear failure so the
		// orchestrator can stop (SCAF-06). Port falls back to the override/default so
		// callers reading Result before checking err still see a sane value.
		res.Port = resolvePort(portOverride, 0)
		return res, fmt.Errorf("no Dockerfile found at %q: a non-T3 project must provide its own image config (pass --dockerfile to point at one)", path)
	}

	res.HasDockerfile = true
	exposePort, hasNonRootUser := parseDockerfile(string(raw))
	res.Port = resolvePort(portOverride, exposePort)
	if !hasNonRootUser {
		res.Warnings = append(res.Warnings,
			"Dockerfile has no non-root USER directive; add e.g. `USER app` so the container does not run as root")
	}
	return res, nil
}

// parseDockerfile does a tolerant, line-based, case-insensitive scan of a Dockerfile,
// returning the first EXPOSE port (0 if none) and whether a non-root USER directive is set.
// It reads only — it never writes.
func parseDockerfile(content string) (exposePort int, hasNonRootUser bool) {
	sc := bufio.NewScanner(strings.NewReader(content))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		directive := strings.ToUpper(fields[0])
		switch directive {
		case "EXPOSE":
			if exposePort == 0 {
				// EXPOSE may carry "8080/tcp"; take the numeric prefix.
				portField := fields[1]
				if i := strings.IndexByte(portField, '/'); i >= 0 {
					portField = portField[:i]
				}
				if p, err := strconv.Atoi(portField); err == nil && p > 0 {
					exposePort = p
				}
			}
		case "USER":
			user := strings.ToLower(fields[1])
			// A non-root USER is any user that is not "root" and not uid 0.
			if user != "root" && user != "0" {
				hasNonRootUser = true
			}
		}
	}
	return exposePort, hasNonRootUser
}

// resolvePort applies the precedence: explicit override > parsed EXPOSE > default (3000).
func resolvePort(override, parsed int) int {
	if override > 0 {
		return override
	}
	if parsed > 0 {
		return parsed
	}
	return defaultPort
}
