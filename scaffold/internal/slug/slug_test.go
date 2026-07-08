package slug

import "testing"

func TestValidate(t *testing.T) {
	cases := []struct {
		name  string
		in    string
		valid bool
	}{
		{"simple lowercase", "myapp", true},
		{"with hyphen and digit", "app-1", true},
		{"two chars min", "ab", true},
		{"31 chars max", "a234567890123456789012345678901", true}, // 1 leading + 30 = 31
		{"uppercase rejected", "MyApp", false},
		{"leading digit rejected", "1app", false},
		{"single char too short", "a", false},
		{"underscore rejected", "app_1", false},
		{"32 chars too long", "a2345678901234567890123456789012", false}, // 1 leading + 31 = 32
		{"empty rejected", "", false},
		{"leading hyphen rejected", "-app", false},
		{"trailing space rejected", "app ", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := Validate(c.in)
			if c.valid && err != nil {
				t.Fatalf("Validate(%q) = %v; want valid", c.in, err)
			}
			if !c.valid && err == nil {
				t.Fatalf("Validate(%q) = nil; want error", c.in)
			}
		})
	}
}

func TestDerive(t *testing.T) {
	cases := []struct {
		name    string
		dir     string
		want    string
		wantErr bool
	}{
		{"coerce mixed case and underscores", "/repos/My_Cool_App", "my-cool-app", false},
		{"trim leading/trailing hyphens", "/tmp/__weird__", "weird", false},
		{"already valid slug", "/home/user/myapp", "myapp", false},
		{"collapse non-alnum to hyphen", "/x/foo.bar.baz", "foo-bar-baz", false},
		{"basename that cannot coerce (all junk)", "/x/___", "", true},
		{"basename too short after coercion", "/x/a", "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Derive(c.dir)
			if c.wantErr {
				if err == nil {
					t.Fatalf("Derive(%q) = %q, nil; want error", c.dir, got)
				}
				if got != "" {
					t.Fatalf("Derive(%q) returned non-empty slug %q on error; must not emit invalid slug", c.dir, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("Derive(%q) unexpected error: %v", c.dir, err)
			}
			if got != c.want {
				t.Fatalf("Derive(%q) = %q; want %q", c.dir, got, c.want)
			}
			// A derived slug must always itself validate.
			if err := Validate(got); err != nil {
				t.Fatalf("Derive(%q) produced slug %q that fails Validate: %v", c.dir, got, err)
			}
		})
	}
}

// A --slug override is validated with the same regex and rejected identically.
func TestOverrideUsesSameValidation(t *testing.T) {
	if err := Validate("Bad_Override"); err == nil {
		t.Fatal("expected malformed --slug override to be rejected by Validate")
	}
	if err := Validate("good-override"); err != nil {
		t.Fatalf("expected valid --slug override to pass Validate, got %v", err)
	}
}
