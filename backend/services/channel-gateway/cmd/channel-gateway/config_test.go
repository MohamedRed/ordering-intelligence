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

func TestLoadConfigRequiresStrictChannelSecretsInProdAlias(t *testing.T) {
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("CORS_ORIGINS", "https://telegram-mini-oi2.web.app")
	t.Setenv("ENVIRONMENT", "prod")

	if _, err := loadConfig(); err == nil {
		t.Fatal("expected prod config to require channel auth secrets")
	}
}

func TestLoadConfigAcceptsStrictChannelSecrets(t *testing.T) {
	t.Setenv("FIRESTORE_PROJECT_ID", "test-project")
	t.Setenv("CORS_ORIGINS", "https://telegram-mini-oi2.web.app")
	t.Setenv("ENVIRONMENT", "staging")
	t.Setenv("TELEGRAM_BOT_TOKEN", "bot-token")
	t.Setenv("TELEGRAM_WEBHOOK_SECRET", "telegram-secret")
	t.Setenv("MOBILE_SESSION_SHARED_SECRET", "mobile-secret")

	cfg, err := loadConfig()
	if err != nil {
		t.Fatalf("unexpected loadConfig error: %v", err)
	}
	if cfg.MobileSessionSecret != "mobile-secret" {
		t.Fatalf("unexpected mobile session secret: %q", cfg.MobileSessionSecret)
	}
}

func TestParseTelegramInitDataDoesNotUseDevIdentityInStrictEnvironments(t *testing.T) {
	for _, env := range []string{"prod", "production", "staging"} {
		t.Run(env, func(t *testing.T) {
			_, err := parseTelegramInitData("", &serviceConfig{Environment: env})
			if err == nil {
				t.Fatal("expected missing init data to fail in strict environment")
			}
		})
	}
}

func TestVerifyMobileSessionRequiresSecretInStrictEnvironments(t *testing.T) {
	for _, env := range []string{"prod", "production", "staging"} {
		t.Run(env, func(t *testing.T) {
			err := verifyMobileSessionAuth(&serviceConfig{Environment: env}, "telegram", "user-1", mobileAuthContext{})
			if err != errMobileAuthNotSupported {
				t.Fatalf("expected errMobileAuthNotSupported, got %v", err)
			}
		})
	}
}
