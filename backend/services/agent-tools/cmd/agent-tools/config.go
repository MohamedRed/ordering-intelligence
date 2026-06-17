package main

import (
	"fmt"
	"os"
	"strings"

	sharedconfig "github.com/ordering-intelligence/sharedconfig"
)

type serviceConfig struct {
	Port               string
	Environment        string
	OrderServiceURL    string
	WaitTimeServiceURL string
	DispatchServiceURL string
	DeliveryServiceURL string
	PaymentsServiceURL string

	OAuthClientID     string
	OAuthClientSecret string

	JWTSigningSecret string
	JWTIssuer        string
	JWTAudience      string
	TokenTTLSeconds  int

	// Voice menu (Gemini + caching)
	ProjectID                string
	FirestoreProjectID       string
	VertexLocation           string
	GeminiModel              string
	VoiceMenuCacheTTLSeconds int
	RedisAddr                string
	RedisPassword            string
	RedisDB                  int
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("agent-tools", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8087"
	}

	tokenTTL := intOrDefault(values["TOKEN_TTL_SECONDS"], 900)
	if tokenTTL < 60 {
		tokenTTL = 60
	}

	cfg := &serviceConfig{
		Port:            port,
		Environment:     stringOrDefault(values["ENVIRONMENT"], "development"),
		OrderServiceURL: strings.TrimSpace(stringOrDefault(values["ORDER_SERVICE_URL"], "")),
		WaitTimeServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("WAIT_TIME_SERVICE_URL"),
			stringOrDefault(values["WAIT_TIME_SERVICE_URL"], ""),
		)),
		PaymentsServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("PAYMENTS_SERVICE_URL"),
			stringOrDefault(values["PAYMENTS_SERVICE_URL"], ""),
		)),
		DispatchServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISPATCH_SERVICE_URL"),
			stringOrDefault(values["DISPATCH_SERVICE_URL"], ""),
		)),
		DeliveryServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DELIVERY_SERVICE_URL"),
			stringOrDefault(values["DELIVERY_SERVICE_URL"], ""),
		)),

		OAuthClientID:     strings.TrimSpace(stringOrDefault(values["OAUTH_CLIENT_ID"], "")),
		OAuthClientSecret: strings.TrimSpace(os.Getenv("OAUTH_CLIENT_SECRET")),

		JWTSigningSecret: strings.TrimSpace(os.Getenv("JWT_SIGNING_SECRET")),
		JWTIssuer:        strings.TrimSpace(stringOrDefault(values["JWT_ISSUER"], "ordering-intelligence")),
		JWTAudience:      strings.TrimSpace(stringOrDefault(values["JWT_AUDIENCE"], "agent-tools")),
		TokenTTLSeconds:  tokenTTL,

		ProjectID:                firstNonEmpty(strings.TrimSpace(os.Getenv("GOOGLE_CLOUD_PROJECT")), strings.TrimSpace(os.Getenv("GCP_PROJECT")), strings.TrimSpace(stringOrDefault(values["PROJECT_ID"], ""))),
		FirestoreProjectID:       strings.TrimSpace(stringOrDefault(values["FIRESTORE_PROJECT_ID"], "")),
		VertexLocation:           firstNonEmpty(strings.TrimSpace(os.Getenv("VERTEX_LOCATION")), strings.TrimSpace(stringOrDefault(values["VERTEX_LOCATION"], "")), "us-central1"),
		GeminiModel:              firstNonEmpty(strings.TrimSpace(os.Getenv("GEMINI_MODEL")), strings.TrimSpace(stringOrDefault(values["GEMINI_MODEL"], ""))),
		VoiceMenuCacheTTLSeconds: intOrDefault(values["VOICE_MENU_CACHE_TTL_SECONDS"], 86400),
		RedisAddr:                firstNonEmpty(strings.TrimSpace(os.Getenv("REDIS_ADDR")), strings.TrimSpace(os.Getenv("MEMORYSTORE_REDIS_ADDR")), strings.TrimSpace(stringOrDefault(values["REDIS_ADDR"], ""))),
		RedisPassword:            strings.TrimSpace(os.Getenv("REDIS_PASSWORD")),
		RedisDB:                  intOrDefault(values["REDIS_DB"], intFromEnv("REDIS_DB", 0)),
	}
	if cfg.FirestoreProjectID == "" {
		cfg.FirestoreProjectID = cfg.ProjectID
	}
	if cfg.VoiceMenuCacheTTLSeconds < 60 {
		cfg.VoiceMenuCacheTTLSeconds = 60
	}

	if cfg.OrderServiceURL == "" {
		return nil, fmt.Errorf("ORDER_SERVICE_URL not configured")
	}
	if cfg.OAuthClientID == "" || cfg.OAuthClientSecret == "" {
		return nil, fmt.Errorf("OAuth client credentials not configured (OAUTH_CLIENT_ID/OAUTH_CLIENT_SECRET)")
	}
	if cfg.JWTSigningSecret == "" {
		return nil, fmt.Errorf("JWT_SIGNING_SECRET not configured")
	}
	return cfg, nil
}
