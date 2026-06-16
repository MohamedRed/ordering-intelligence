package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"firebase.google.com/go/v4/auth"
	"github.com/joho/godotenv"
)

const tenantsCollection = "tenants"
const agentRoutesCollection = "agent_routes"
const agentWebhookEventsCollection = "agent_webhook_events"
const channelRoutesCollection = "channel_routes"

// serviceConfig stores environment configuration for the admin service.
type serviceConfig struct {
	Port        string
	Environment string
	ProjectID   string
	Credentials string
	RequireAuth bool
	CORSOrigins []string
}

// tenant represents a business tenant managed by the platform.
type tenant struct {
	ID           string          `json:"id" firestore:"id"`
	Name         string          `json:"name" firestore:"name"`
	PrimaryUser  string          `json:"primaryUser" firestore:"primaryUser"`
	Status       string          `json:"status" firestore:"status"`
	FeatureFlags map[string]bool `json:"featureFlags" firestore:"featureFlags"`
	StoreID      string          `json:"storeId" firestore:"storeId"`
	BusinessType string          `json:"businessType" firestore:"businessType"`
	Timezone     string          `json:"timezone" firestore:"timezone"`
	Phone        string          `json:"phone" firestore:"phone"`
	CreatedAt    time.Time       `json:"createdAt" firestore:"createdAt"`
	UpdatedAt    time.Time       `json:"updatedAt" firestore:"updatedAt"`
}

// tenantRequest describes expected payload for tenant creation/update.
type tenantRequest struct {
	Name         string          `json:"name"`
	PrimaryUser  string          `json:"primaryUser"`
	Status       string          `json:"status"`
	FeatureFlags map[string]bool `json:"featureFlags"`
	StoreID      string          `json:"storeId"`
	BusinessType string          `json:"businessType"`
	Timezone     string          `json:"timezone"`
	Phone        string          `json:"phone"`
}

type channelRouteRequest struct {
	Channel      string `json:"channel"`
	AccountID    string `json:"accountId"`
	TenantID     string `json:"tenantId"`
	StoreID      string `json:"storeId"`
	BusinessType string `json:"businessType"`
	AgentID      string `json:"agentId"`
}

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	ctx := context.Background()
	firestoreClient, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer firestoreClient.Close()

	var authClient *auth.Client
	if cfg.RequireAuth {
		authClient, err = newFirebaseAuthClient(ctx, cfg)
		if err != nil {
			log.Fatalf("failed to create firebase auth client: %v", err)
		}
	}

	router := newRouter(ctx, cfg, firestoreClient, authClient)

	log.Printf("Admin service listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
