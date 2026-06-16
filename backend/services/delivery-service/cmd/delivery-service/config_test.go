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

func TestLoadConfigRejectsMockProviderModeInProduction(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("PROVIDER_MODE", "mock")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject mock provider mode in production")
	}
}

func TestLoadConfigAcceptsLiveProviderModeWithCredentialsInProduction(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("PROVIDER_MODE", "live")
	t.Setenv("UBER_DIRECT_CUSTOMER_ID", "customer-123")
	t.Setenv("UBER_DIRECT_ACCESS_TOKEN", "token-123")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if cfg.ProviderMode != deliveryProviderModeLive {
		t.Fatalf("expected live provider mode, got %q", cfg.ProviderMode)
	}
}
