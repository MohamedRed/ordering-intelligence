package main

import "testing"

func setRequiredConfigEnv(t *testing.T) {
	t.Helper()
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("ORDER_SERVICE_URL", "https://order-service.example.com")
	t.Setenv("CORS_ORIGINS", "https://driver.example.com")
	t.Setenv("ORDERS_EVENTS_OIDC_AUDIENCE", "https://dispatch.example.com")
	t.Setenv("ORDERS_EVENTS_OIDC_ALLOWED_EMAILS", "orders-events@test-project.iam.gserviceaccount.com")
	t.Setenv("CLOUD_TASKS_OIDC_AUDIENCE", "https://dispatch.example.com")
	t.Setenv("CLOUD_TASKS_OIDC_ALLOWED_EMAILS", "dispatch-tasks@test-project.iam.gserviceaccount.com")
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
	if cfg.OrdersEventsOIDCAudience != "https://dispatch.example.com" {
		t.Fatalf("unexpected orders-events audience: %q", cfg.OrdersEventsOIDCAudience)
	}
	if len(cfg.OrdersEventsOIDCAllowedEmails) != 1 || cfg.OrdersEventsOIDCAllowedEmails[0] != "orders-events@test-project.iam.gserviceaccount.com" {
		t.Fatalf("unexpected orders-events allowlist: %#v", cfg.OrdersEventsOIDCAllowedEmails)
	}
	if cfg.CloudTasksOIDCAudience != "https://dispatch.example.com" {
		t.Fatalf("unexpected Cloud Tasks audience: %q", cfg.CloudTasksOIDCAudience)
	}
	if len(cfg.CloudTasksOIDCAllowedEmails) != 1 || cfg.CloudTasksOIDCAllowedEmails[0] != "dispatch-tasks@test-project.iam.gserviceaccount.com" {
		t.Fatalf("unexpected Cloud Tasks allowlist: %#v", cfg.CloudTasksOIDCAllowedEmails)
	}
}

func TestLoadConfigRejectsWildcardCORSOrigins(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("CORS_ORIGINS", "*")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject wildcard CORS origins")
	}
}

func TestLoadConfigRejectsMissingTaskAuthWhenAuthRequired(t *testing.T) {
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("ORDER_SERVICE_URL", "https://order-service.example.com")
	t.Setenv("CORS_ORIGINS", "https://driver.example.com")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject missing task auth values")
	}
}

func TestLoadConfigRejectsDisabledAuthInStrictEnvironment(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("ENVIRONMENT", "prod")
	t.Setenv("REQUIRE_AUTH", "false")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject disabled auth in strict environment")
	}
}

func TestLoadConfigRequiresInternalAuthInStrictEnvironment(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("ENVIRONMENT", "staging")
	t.Setenv("INTERNAL_AUTH_AUDIENCE", "")
	t.Setenv("INTERNAL_ALLOWED_EMAILS", "")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected loadConfig to reject missing internal auth in strict environment")
	}
}

func TestLoadConfigAcceptsStrictAuthConfig(t *testing.T) {
	setRequiredConfigEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("INTERNAL_AUTH_AUDIENCE", "https://dispatch.example.com")
	t.Setenv("INTERNAL_ALLOWED_EMAILS", "agent-tools@test-project.iam.gserviceaccount.com")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if !cfg.RequireAuth {
		t.Fatal("expected auth to remain enabled")
	}
	if cfg.InternalAuthAudience != "https://dispatch.example.com" {
		t.Fatalf("unexpected internal audience: %q", cfg.InternalAuthAudience)
	}
}
