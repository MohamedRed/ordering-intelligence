package main

import "testing"

func setRequiredConfigEnv(t *testing.T) {
	t.Helper()
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("ORDER_SERVICE_URL", "https://order-service.example.com")
	t.Setenv("CORS_ORIGINS", "https://driver.example.com")
}

func TestLoadConfigIncludesExplicitCORSOrigins(t *testing.T) {
	setRequiredConfigEnv(t)

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if len(cfg.CORSOrigins) != 1 || cfg.CORSOrigins[0] != "https://driver.example.com" {
		t.Fatalf("unexpected CORS origins: %#v", cfg.CORSOrigins)
	}
}

func TestLoadConfigRejectsWildcardCORSOrigins(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("CORS_ORIGINS", "*")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject wildcard CORS origins")
	}
}
