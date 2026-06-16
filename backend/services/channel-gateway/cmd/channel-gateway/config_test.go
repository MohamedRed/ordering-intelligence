package main

import "testing"

func TestLoadConfigRequiresCORSOrigins(t *testing.T) {
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("CORS_ORIGINS", "")

	if _, err := loadConfig(); err == nil {
		t.Fatalf("expected missing CORS_ORIGINS to fail")
	}
}

func TestLoadConfigLoadsCORSOrigins(t *testing.T) {
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("CORS_ORIGINS", "https://telegram-mini-oi2.web.app,http://localhost:3000")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	want := []string{"https://telegram-mini-oi2.web.app", "http://localhost:3000"}
	if len(cfg.CORSOrigins) != len(want) {
		t.Fatalf("expected %d origins, got %d: %#v", len(want), len(cfg.CORSOrigins), cfg.CORSOrigins)
	}
	for i := range want {
		if cfg.CORSOrigins[i] != want[i] {
			t.Fatalf("origin[%d] expected %q, got %q", i, want[i], cfg.CORSOrigins[i])
		}
	}
}
