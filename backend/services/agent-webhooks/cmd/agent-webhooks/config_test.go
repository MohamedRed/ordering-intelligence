package main

import "testing"

func setAgentWebhookRequiredEnv(t *testing.T) {
	t.Helper()
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("ELEVENLABS_CONVERSATION_INIT_SECRET", "")
	t.Setenv("AGENT_WEBHOOK_SECRET", "")
}

func TestLoadConfigRejectsMissingSecretInProduction(t *testing.T) {
	setAgentWebhookRequiredEnv(t)
	t.Setenv("ENVIRONMENT", "production")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected production config to require ELEVENLABS_CONVERSATION_INIT_SECRET")
	}
}

func TestLoadConfigAcceptsConversationInitSecretInProduction(t *testing.T) {
	setAgentWebhookRequiredEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("ELEVENLABS_CONVERSATION_INIT_SECRET", "secret-123")
	t.Setenv("INTERNAL_AUTH_AUDIENCE", "https://agent-webhooks.example.com")
	t.Setenv("INTERNAL_ALLOWED_EMAILS", "agent-tools@test-project.iam.gserviceaccount.com")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if cfg.Secret != "secret-123" {
		t.Fatalf("unexpected secret value: %q", cfg.Secret)
	}
	if cfg.InternalAuthAudience != "https://agent-webhooks.example.com" {
		t.Fatalf("unexpected internal audience: %q", cfg.InternalAuthAudience)
	}
}

func TestLoadConfigAllowsMissingSecretInDevelopment(t *testing.T) {
	setAgentWebhookRequiredEnv(t)
	t.Setenv("ENVIRONMENT", "development")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if cfg.Secret != "" {
		t.Fatalf("expected empty development secret, got %q", cfg.Secret)
	}
}

func TestLoadConfigRequiresInternalAuthInProduction(t *testing.T) {
	setAgentWebhookRequiredEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("ELEVENLABS_CONVERSATION_INIT_SECRET", "secret-123")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected production config to require internal auth settings")
	}
}
