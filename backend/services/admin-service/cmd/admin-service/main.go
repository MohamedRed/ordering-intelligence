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
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
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

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	router.Use(corsMiddleware(cfg.CORSOrigins))
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

	router.Get("/channel-routes", func(w http.ResponseWriter, r *http.Request) {
		routes, err := listChannelRoutes(ctx, firestoreClient)
		if err != nil {
			log.Printf("failed to list channel routes: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
			return
		}
		writeJSON(w, http.StatusOK, routes)
	})

	router.Post("/channel-routes", func(w http.ResponseWriter, r *http.Request) {
		var payload channelRouteRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		payload.Channel = strings.TrimSpace(payload.Channel)
		payload.AccountID = strings.TrimSpace(payload.AccountID)
		payload.TenantID = strings.TrimSpace(payload.TenantID)
		payload.StoreID = strings.TrimSpace(payload.StoreID)
		payload.BusinessType = strings.TrimSpace(payload.BusinessType)
		payload.AgentID = strings.TrimSpace(payload.AgentID)

		if payload.Channel == "" || payload.AccountID == "" || payload.AgentID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		docID := strings.ToLower(payload.Channel) + "_" + payload.AccountID
		now := time.Now().UTC()
		doc := map[string]any{
			"id":            docID,
			"channel":       payload.Channel,
			"account_id":    payload.AccountID,
			"tenant_id":     payload.TenantID,
			"store_id":      payload.StoreID,
			"business_type": payload.BusinessType,
			"agent_id":      payload.AgentID,
			"updated_at":    now,
		}

		existing, err := firestoreClient.Collection(channelRoutesCollection).Doc(docID).Get(ctx)
		if err == nil && existing.Exists() {
			if createdAt, ok := existing.Data()["created_at"]; ok {
				doc["created_at"] = createdAt
			}
		} else if status.Code(err) == codes.NotFound || err == nil {
			doc["created_at"] = now
		} else if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("failed to fetch channel route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}

		if _, err := firestoreClient.Collection(channelRoutesCollection).Doc(docID).Set(ctx, doc, cloudfirestore.MergeAll); err != nil {
			log.Printf("failed to upsert channel route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "write_failed"})
			return
		}
		writeJSON(w, http.StatusOK, doc)
	})

	// Demo helper: map an ElevenLabs agent ID to a tenant/store for widget-based demos.
	// This is useful when conversations are initiated from the web widget (no phone_number_id/to_number available),
	// and agent-webhooks needs a deterministic way to inject tenant context.
	router.Post("/demo/agent-route", func(w http.ResponseWriter, r *http.Request) {
		var payload struct {
			AgentID                 string   `json:"agentId"`
			TenantID                string   `json:"tenantId"`
			StoreID                 string   `json:"storeId"`
			BusinessType            string   `json:"businessType"`
			Environment             string   `json:"environment"`
			DemoSessionID           string   `json:"demoSessionId"`
			DemoCallerID            string   `json:"demoCallerId"`
			DemoCallSid             string   `json:"demoCallSid"`
			DemoCustomerName        string   `json:"demoCustomerName"`
			DemoIsReturningCustomer *bool    `json:"demoIsReturningCustomer"`
			DemoTopReorders         []string `json:"demoTopReorders"`
			DemoETAMinutes          *int     `json:"demoEtaMinutes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.AgentID = strings.TrimSpace(payload.AgentID)
		payload.TenantID = strings.TrimSpace(payload.TenantID)
		payload.StoreID = strings.TrimSpace(payload.StoreID)
		payload.BusinessType = strings.TrimSpace(payload.BusinessType)
		if payload.AgentID == "" || payload.StoreID == "" || payload.TenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		docID := "agent_" + payload.AgentID
		now := time.Now().UTC()
		doc := map[string]any{
			"agent_id":        payload.AgentID,
			"tenant_id":       payload.TenantID,
			"store_id":        payload.StoreID,
			"business_type":   payload.BusinessType,
			"environment":     payload.Environment,
			"demo_session_id": payload.DemoSessionID,
			"updated_at":      now,
			"created_at":      now,
		}
		if strings.TrimSpace(payload.DemoCallerID) != "" {
			doc["demo_caller_id"] = strings.TrimSpace(payload.DemoCallerID)
		}
		if strings.TrimSpace(payload.DemoCallSid) != "" {
			doc["demo_call_sid"] = strings.TrimSpace(payload.DemoCallSid)
		}
		if strings.TrimSpace(payload.DemoCustomerName) != "" {
			doc["demo_customer_name"] = strings.TrimSpace(payload.DemoCustomerName)
		}
		if payload.DemoIsReturningCustomer != nil {
			doc["demo_is_returning_customer"] = *payload.DemoIsReturningCustomer
		}
		if len(payload.DemoTopReorders) > 0 {
			doc["demo_top_reorders"] = payload.DemoTopReorders
		}
		if payload.DemoETAMinutes != nil && *payload.DemoETAMinutes > 0 {
			doc["demo_eta_minutes"] = *payload.DemoETAMinutes
		}
		_, err := firestoreClient.Collection(agentRoutesCollection).Doc(docID).Set(ctx, doc, cloudfirestore.MergeAll)
		if err != nil {
			log.Printf("failed to upsert agent route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "write_failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":      true,
			"agentId": payload.AgentID,
			"docId":   docID,
		})
	})

	// Demo helper: fetch current route + last observed webhook variables for an agent ID.
	// This lets the admin UI verify the agent actually received the expected dynamic variables.
	router.Get("/demo/agent-route/{agentId}", func(w http.ResponseWriter, r *http.Request) {
		agentID := strings.TrimSpace(chi.URLParam(r, "agentId"))
		if agentID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_agent_id"})
			return
		}

		ctx2, cancel := context.WithTimeout(r.Context(), 4*time.Second)
		defer cancel()

		docID := "agent_" + agentID

		var route map[string]any
		routeSnap, err := firestoreClient.Collection(agentRoutesCollection).Doc(docID).Get(ctx2)
		if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("demo route fetch failed agent=%s err=%v", agentID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if err == nil && routeSnap.Exists() {
			route = routeSnap.Data()
		}

		var lastEvent map[string]any
		evSnap, err := firestoreClient.Collection(agentWebhookEventsCollection).Doc(docID).Get(ctx2)
		if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("demo last event fetch failed agent=%s err=%v", agentID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if err == nil && evSnap.Exists() {
			lastEvent = evSnap.Data()
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"ok":        true,
			"agentId":   agentID,
			"route":     route,
			"lastEvent": lastEvent,
		})
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
		CORSOrigins: parseCORSOrigins(os.Getenv("CORS_ORIGINS")),
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

func parseCORSOrigins(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return []string{"*"}
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		out = append(out, p)
	}
	if len(out) == 0 {
		return []string{"*"}
	}
	return out
}

func corsMiddleware(allowedOrigins []string) func(http.Handler) http.Handler {
	allowAll := false
	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, o := range allowedOrigins {
		if o == "*" {
			allowAll = true
			continue
		}
		allowed[o] = struct{}{}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" {
				if allowAll {
					// Echo origin (safe for our token-based auth; avoids '*' issues with some clients).
					w.Header().Set("Access-Control-Allow-Origin", origin)
					w.Header().Add("Vary", "Origin")
				} else {
					if _, ok := allowed[origin]; ok {
						w.Header().Set("Access-Control-Allow-Origin", origin)
						w.Header().Add("Vary", "Origin")
					}
				}

				// Always advertise supported methods/headers for preflight.
				w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,DELETE,OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization,Content-Type")
				w.Header().Set("Access-Control-Max-Age", "600")
			}

			if r.Method == http.MethodOptions {
				// Short-circuit preflight before auth middleware.
				w.WriteHeader(http.StatusNoContent)
				return
			}

			next.ServeHTTP(w, r)
		})
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

func listChannelRoutes(ctx context.Context, client *cloudfirestore.Client) ([]map[string]any, error) {
	iter := client.Collection(channelRoutesCollection).Documents(ctx)
	defer iter.Stop()

	var routes []map[string]any
	for {
		doc, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		data := doc.Data()
		data["id"] = doc.Ref.ID
		routes = append(routes, data)
	}
	return routes, nil
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
