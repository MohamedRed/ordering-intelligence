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
	Port             string
	Environment      string
	FirestoreProject string
	CredentialsFile  string
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("customer-profile-service", nil)
	if err != nil {
		return nil, err
	}
	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	project := strings.TrimSpace(stringOrDefault(values["FIRESTORE_PROJECT_ID"], strings.TrimSpace(os.Getenv("FIRESTORE_PROJECT_ID"))))
	if project == "" {
		project = strings.TrimSpace(os.Getenv("GOOGLE_CLOUD_PROJECT"))
	}
	if project == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}
	return &serviceConfig{
		Port:             port,
		Environment:      strings.TrimSpace(stringOrDefault(values["ENVIRONMENT"], "development")),
		FirestoreProject: project,
		CredentialsFile:  strings.TrimSpace(stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], "")),
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	var opts []option.ClientOption
	if cfg.CredentialsFile != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}
	return cloudfirestore.NewClient(ctx, cfg.FirestoreProject, opts...)
}
