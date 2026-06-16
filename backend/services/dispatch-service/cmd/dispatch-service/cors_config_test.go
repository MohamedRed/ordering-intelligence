package main

import "testing"

func TestResolveDispatchCORSOrigins(t *testing.T) {
	origins, err := resolveDispatchCORSOrigins("https://driver.example.com/, https://driver.example.com, http://localhost:3000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := []string{"https://driver.example.com", "http://localhost:3000"}
	if len(origins) != len(expected) {
		t.Fatalf("expected %d origins, got %#v", len(expected), origins)
	}
	for i := range expected {
		if origins[i] != expected[i] {
			t.Fatalf("origin %d: expected %q, got %q", i, expected[i], origins[i])
		}
	}
}

func TestResolveDispatchCORSOriginsRejectsUnsafeValues(t *testing.T) {
	cases := []string{
		"",
		"*",
		"https://*.example.com",
		"https://driver.example.com/path",
		"ftp://driver.example.com",
	}
	for _, tc := range cases {
		t.Run(tc, func(t *testing.T) {
			if _, err := resolveDispatchCORSOrigins(tc); err == nil {
				t.Fatalf("expected error for %q", tc)
			}
		})
	}
}

func TestDispatchCORSOptionsUsesExplicitOrigins(t *testing.T) {
	options := dispatchCORSOptions([]string{"https://driver.example.com"})
	if len(options.AllowedOrigins) != 1 || options.AllowedOrigins[0] != "https://driver.example.com" {
		t.Fatalf("unexpected allowed origins: %#v", options.AllowedOrigins)
	}
	if !options.AllowCredentials {
		t.Fatal("expected credentials to stay enabled for authenticated browser requests")
	}
}
