package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const tenantsCollection = "tenants"

// serviceConfig stores environment configuration for the admin service.
type serviceConfig struct {
	Port        string
	Environment string
	ProjectID   string
	Credentials string
	RequireAuth bool
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

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	if cfg.RequireAuth && authClient != nil {
		router.Use(firebaseAuthMiddleware(authClient))
	}

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "admin-service",
			"environment": cfg.Environment,
		})
	})

	router.Get("/tenants", func(w http.ResponseWriter, r *http.Request) {
		tenants, err := listTenants(ctx, firestoreClient)
		if err != nil {
			log.Printf("failed to list tenants: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
			return
		}
		writeJSON(w, http.StatusOK, tenants)
	})

	router.Post("/tenants", func(w http.ResponseWriter, r *http.Request) {
		var payload tenantRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.Name == "" || payload.PrimaryUser == "" || payload.StoreID == "" || payload.BusinessType == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		tenantRecord := tenant{
			ID:           generateTenantID(),
			Name:         payload.Name,
			PrimaryUser:  payload.PrimaryUser,
			Status:       defaultStatus(payload.Status),
			FeatureFlags: payload.FeatureFlags,
			StoreID:      payload.StoreID,
			BusinessType: payload.BusinessType,
			Timezone:     payload.Timezone,
			Phone:        payload.Phone,
			CreatedAt:    time.Now().UTC(),
			UpdatedAt:    time.Now().UTC(),
		}

		if err := createTenant(ctx, firestoreClient, tenantRecord); err != nil {
			log.Printf("failed to create tenant: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "create_failed"})
			return
		}

		_ = logAudit(ctx, firestoreClient, "tenant_created", tenantRecord.ID, payload.PrimaryUser)
		writeJSON(w, http.StatusCreated, tenantRecord)
	})

	router.Get("/tenants/{tenantID}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "tenantID")
		if id == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_tenant_id"})
			return
		}

		record, err := fetchTenant(ctx, firestoreClient, id)
		if err != nil {
			log.Printf("failed to fetch tenant: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if record == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			return
		}

		writeJSON(w, http.StatusOK, record)
	})

	router.Patch("/tenants/{tenantID}/feature-flags", func(w http.ResponseWriter, r *http.Request) {
		tenantID := chi.URLParam(r, "tenantID")
		if tenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_tenant_id"})
			return
		}

		var payload map[string]bool
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		updated, err := updateTenantFlags(ctx, firestoreClient, tenantID, payload)
		if err != nil {
			if errors.Is(err, errTenantNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
				return
			}
			log.Printf("failed updating flags: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}

		_ = logAudit(ctx, firestoreClient, "flags_updated", tenantID, "system")
		writeJSON(w, http.StatusOK, updated)
	})

	log.Printf("Admin service listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("admin-service", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8085"
	}

	return &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		RequireAuth: stringOrDefault(values["REQUIRE_AUTH"], "true") == "true",
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

func listTenants(ctx context.Context, client *cloudfirestore.Client) ([]tenant, error) {
	snapshots, err := client.Collection(tenantsCollection).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}

	result := make([]tenant, 0, len(snapshots))
	for _, snap := range snapshots {
		var entry tenant
		if err := snap.DataTo(&entry); err != nil {
			return nil, err
		}
		result = append(result, entry)
	}
	return result, nil
}

func createTenant(ctx context.Context, client *cloudfirestore.Client, record tenant) error {
	doc := client.Collection(tenantsCollection).Doc(record.ID)
	_, err := doc.Create(ctx, record)
	return err
}

func fetchTenant(ctx context.Context, client *cloudfirestore.Client, tenantID string) (*tenant, error) {
	snapshot, err := client.Collection(tenantsCollection).Doc(tenantID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, errTenantNotFound
		}
		return nil, err
	}

	var entry tenant
	if err := snapshot.DataTo(&entry); err != nil {
		return nil, err
	}
	return &entry, nil
}

type auditRecord struct {
	Action     string    `firestore:"action"`
	TenantID   string    `firestore:"tenantId"`
	Actor      string    `firestore:"actor"`
	OccurredAt time.Time `firestore:"occurredAt"`
}

func logAudit(ctx context.Context, client *cloudfirestore.Client, action string, tenantID string, actor string) error {
	record := auditRecord{
		Action:     action,
		TenantID:   tenantID,
		Actor:      actor,
		OccurredAt: time.Now().UTC(),
	}
	_, _, err := client.Collection("audits").Add(ctx, record)
	return err
}

var errTenantNotFound = errors.New("tenant_not_found")

func updateTenantFlags(ctx context.Context, client *cloudfirestore.Client, tenantID string, flags map[string]bool) (*tenant, error) {
	docRef := client.Collection(tenantsCollection).Doc(tenantID)
	_, err := docRef.Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, errTenantNotFound
		}
		return nil, err
	}
	if flags == nil {
		flags = map[string]bool{}
	}
	if _, err := docRef.Update(ctx, []cloudfirestore.Update{{Path: "featureFlags", Value: flags}, {Path: "updatedAt", Value: time.Now().UTC()}}); err != nil {
		return nil, err
	}
	return fetchTenant(ctx, client, tenantID)
}

func defaultStatus(statusValue string) string {
	if statusValue == "" {
		return "active"
	}
	return statusValue
}

func generateTenantID() string {
	return fmt.Sprintf("tenant-%d", time.Now().UTC().UnixNano())
}

// authMiddleware enforces a simple static API key for admin endpoints.

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing response: %v", err)
	}
}

func newFirebaseAuthClient(ctx context.Context, cfg *serviceConfig) (*auth.Client, error) {
	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: cfg.ProjectID}, opts...)
	if err != nil {
		return nil, err
	}
	return app.Auth(ctx)
}

type tokenVerifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (*auth.Token, error)
}

func firebaseAuthMiddleware(client tokenVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimPrefix(authHeader, "Bearer ")
			if tokenString == authHeader {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}
			token, err := client.VerifyIDToken(r.Context(), tokenString)
			if err != nil {
				log.Printf("auth failed: %v", err)
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			// Require role=admin claim
			if role, ok := token.Claims["role"].(string); !ok || role != "admin" {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func logError(message string) error {
	err := errors.New(message)
	log.Print(err)
	return err
}
