package main

import "testing"

func TestParseCORSOriginsRequiresExplicitOrigins(t *testing.T) {
	for _, raw := range []string{"", " , "} {
		t.Run(raw, func(t *testing.T) {
			if _, err := parseCORSOrigins(raw); err == nil {
				t.Fatalf("expected %q to fail", raw)
			}
		})
	}
}

func TestParseCORSOriginsRejectsWildcards(t *testing.T) {
	invalid := []string{
		"*",
		"https://*.example.com",
		"http://localhost:*",
	}
	for _, raw := range invalid {
		t.Run(raw, func(t *testing.T) {
			if _, err := parseCORSOrigins(raw); err == nil {
				t.Fatalf("expected %q to fail", raw)
			}
		})
	}
}

func TestParseCORSOriginsRejectsInvalidOrigins(t *testing.T) {
	invalid := []string{
		"telegram-mini-oi2.web.app",
		"https://telegram-mini-oi2.web.app/path",
		"https://telegram-mini-oi2.web.app?debug=true",
		"ftp://telegram-mini-oi2.web.app",
	}
	for _, raw := range invalid {
		t.Run(raw, func(t *testing.T) {
			if _, err := parseCORSOrigins(raw); err == nil {
				t.Fatalf("expected %q to fail", raw)
			}
		})
	}
}

func TestParseCORSOriginsTrimsAndDeduplicates(t *testing.T) {
	origins, err := parseCORSOrigins(" https://telegram-mini-oi2.web.app, http://localhost:3000, https://telegram-mini-oi2.web.app ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"https://telegram-mini-oi2.web.app", "http://localhost:3000"}
	if len(origins) != len(want) {
		t.Fatalf("expected %d origins, got %d: %#v", len(want), len(origins), origins)
	}
	for i := range want {
		if origins[i] != want[i] {
			t.Fatalf("origin[%d] expected %q, got %q", i, want[i], origins[i])
		}
	}
}
