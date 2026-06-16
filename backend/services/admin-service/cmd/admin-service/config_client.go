package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"

	cloudfirestore "cloud.google.com/go/firestore"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
)

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("admin-service", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8085"
	}

	corsOrigins, err := parseCORSOrigins(stringOrDefault(values["CORS_ORIGINS"], ""))
	if err != nil {
		return nil, err
	}

	return &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		RequireAuth: stringOrDefault(values["REQUIRE_AUTH"], "true") == "true",
		CORSOrigins: corsOrigins,
	}, nil
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
		return nil, logError("FIRESTORE_PROJECT_ID not configured")
	}

	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}

	return cloudfirestore.NewClient(ctx, cfg.ProjectID, opts...)
}

func logError(message string) error {
	err := errors.New(message)
	log.Print(err)
	return err
}
