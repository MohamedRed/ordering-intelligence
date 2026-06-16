package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
)

type serviceConfig struct {
	Port                      string
	Environment               string
	ProjectID                 string
	Credentials               string
	Secret                    string
	InternalAuthAudience      string
	InternalAllowedEmails     []string
	CustomerProfileServiceURL string
	RecommendationServiceURL  string
	WaitTimeServiceURL        string
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("agent-webhooks", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8086"
	}

	// Keep the same env var name as onboarding for easy migration of the webhook.
	secret := os.Getenv("ELEVENLABS_CONVERSATION_INIT_SECRET")
	if secret == "" {
		secret = os.Getenv("AGENT_WEBHOOK_SECRET")
	}

	cfg := &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		Secret:      strings.TrimSpace(secret),
		InternalAuthAudience: strings.TrimSpace(firstNonEmpty(
			os.Getenv("INTERNAL_AUTH_AUDIENCE"),
			stringOrDefault(values["INTERNAL_AUTH_AUDIENCE"], ""),
		)),
		InternalAllowedEmails: splitCSV(firstNonEmpty(
			os.Getenv("INTERNAL_ALLOWED_EMAILS"),
			stringOrDefault(values["INTERNAL_ALLOWED_EMAILS"], ""),
		)),
		CustomerProfileServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("CUSTOMER_PROFILE_SERVICE_URL"),
			stringOrDefault(values["CUSTOMER_PROFILE_SERVICE_URL"], ""),
		)),
		RecommendationServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("RECOMMENDATION_SERVICE_URL"),
			stringOrDefault(values["RECOMMENDATION_SERVICE_URL"], ""),
		)),
		WaitTimeServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("WAIT_TIME_SERVICE_URL"),
			stringOrDefault(values["WAIT_TIME_SERVICE_URL"], ""),
		)),
	}
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func validateConfig(cfg *serviceConfig) error {
	if isStrictEnvironment(cfg.Environment) && strings.TrimSpace(cfg.Secret) == "" {
		return fmt.Errorf("ELEVENLABS_CONVERSATION_INIT_SECRET is required in %s", cfg.Environment)
	}
	return nil
}

func isStrictEnvironment(environment string) bool {
	switch strings.ToLower(strings.TrimSpace(environment)) {
	case "prod", "production", "staging":
		return true
	default:
		return false
	}
}

func stringOrDefault(value interface{}, fallback string) string {
	switch v := value.(type) {
	case string:
		if v == "" {
			return fallback
		}
		return v
	case int64:
		return fmt.Sprintf("%d", v)
	default:
		return fallback
	}
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	if cfg.ProjectID == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}
	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}
	return cloudfirestore.NewClient(ctx, cfg.ProjectID, opts...)
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		v = strings.TrimSpace(v)
		if v != "" {
			return v
		}
	}
	return ""
}

func splitCSV(value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	var out []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, p)
	}
	return out
}
