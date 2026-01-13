package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	agentcontext "github.com/ordering-intelligence/agentcontext"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
)

const agentWebhookEventsCollection = "agent_webhook_events"

type serviceConfig struct {
	Port                      string
	Environment               string
	ProjectID                 string
	Credentials               string
	Secret                    string
	CustomerProfileServiceURL string
	RecommendationServiceURL  string
	WaitTimeServiceURL        string
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

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "agent-webhooks",
			"environment": cfg.Environment,
		})
	})

	router.Post("/elevenlabs/conversation-init", func(w http.ResponseWriter, r *http.Request) {
		handleConversationInit(w, r, firestoreClient, cfg)
	})

	log.Printf("Agent webhooks service listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
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

	return &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		Secret:      strings.TrimSpace(secret),
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
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}
	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}
	return cloudfirestore.NewClient(ctx, cfg.ProjectID, opts...)
}

func handleConversationInit(
	w http.ResponseWriter,
	r *http.Request,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
) {
	// Optional auth (matches onboarding behavior).
	secret := strings.TrimSpace(cfg.Secret)
	if secret != "" {
		got := strings.TrimSpace(r.Header.Get("x-elevenlabs-conversation-init-secret"))
		if got == "" {
			got = strings.TrimSpace(r.Header.Get("x-onboarding-webhook-secret"))
		}
		if got != secret {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
	}

	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_json"})
		return
	}

	phoneNumberId := firstNonEmpty(
		getString(body, "phone_number_id"),
		getString(body, "phoneNumberId"),
		getStringNested(body, "phone_number", "phone_number_id"),
		getStringNested(body, "phone_number", "id"),
		getStringNested(body, "twilio", "phone_number_id"),
	)
	agentNumber := firstNonEmpty(
		getString(body, "agent_number"),
		getString(body, "agentNumber"),
		getString(body, "to_number"),
		getString(body, "toNumber"),
		getString(body, "agent_phone_number"),
		getStringNested(body, "twilio", "agent_number"),
	)
	agentID := firstNonEmpty(
		getString(body, "agent_id"),
		getString(body, "agentId"),
		getStringNested(body, "agent", "agent_id"),
		getStringNested(body, "agent", "id"),
	)
	callerID := firstNonEmpty(
		getString(body, "caller_id"),
		getString(body, "callerId"),
		getStringNested(body, "twilio", "caller_id"),
		getStringNested(body, "twilio", "callerId"),
	)
	callSid := firstNonEmpty(
		getString(body, "call_sid"),
		getString(body, "callSid"),
		getStringNested(body, "twilio", "call_sid"),
		getStringNested(body, "twilio", "callSid"),
	)
	calledNumber := firstNonEmpty(
		getString(body, "called_number"),
		getString(body, "calledNumber"),
		getStringNested(body, "twilio", "called_number"),
		getStringNested(body, "twilio", "calledNumber"),
	)

	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()

	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		PhoneNumberID: phoneNumberId,
		AgentNumber:   agentNumber,
		AgentID:       agentID,
	})
	if err != nil {
		log.Printf("conversation-init: route lookup failed err=%v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "route_lookup_failed"})
		return
	}

	if route == nil {
		log.Printf("conversation-init: no mapping found phoneNumberId=%v agentNumber=%v agentId=%v", orNull(phoneNumberId), maskPhone(agentNumber), orNull(agentID))
		writeJSON(w, http.StatusOK, map[string]any{"dynamic_variables": map[string]any{}})
		return
	}

	dyn := agentcontext.BuildDynamicVariables(
		ctx,
		*route,
		agentcontext.DynamicVarsInput{
			CallerID:      callerID,
			CallSid:       callSid,
			AgentID:       agentID,
			AgentNumber:   agentNumber,
			PhoneNumberID: phoneNumberId,
			CalledNumber:  calledNumber,
		},
		agentcontext.ServicesConfig{
			CustomerProfileServiceURL: cfg.CustomerProfileServiceURL,
			RecommendationServiceURL:  cfg.RecommendationServiceURL,
			WaitTimeServiceURL:        cfg.WaitTimeServiceURL,
		},
		agentcontext.DynamicVarsOptions{},
	)

	// Best-effort: store the last computed dynamic variables so the admin demo page can verify
	// what the agent actually received (without needing the ElevenLabs secret).
	if strings.TrimSpace(agentID) != "" {
		storeID := strings.TrimSpace(anyToString(dyn["storeId"]))
		tenantID := strings.TrimSpace(anyToString(dyn["tenantId"]))
		businessType := strings.TrimSpace(anyToString(dyn["businessType"]))
		onboardingSessionID := strings.TrimSpace(anyToString(dyn["onboardingSessionId"]))
		agentNumberClean := strings.TrimSpace(anyToString(dyn["agentNumber"]))
		storeLastConversationInitEvent(r.Context(), firestoreClient, map[string]any{
			"agent_id":              agentID,
			"received_at":           time.Now().UTC(),
			"route_source":          route.Source,
			"route_doc_id":          route.DocID,
			"phone_number_id":       phoneNumberId,
			"to_number":             agentNumberClean,
			"caller_id":             maskPhone(callerID),
			"call_sid":              orNull(callSid),
			"tenant_id":             tenantID,
			"store_id":              storeID,
			"business_type":         businessType,
			"onboarding_session_id": onboardingSessionID,
			"dynamic_variables":     dyn,
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{"dynamic_variables": dyn})
}

func storeLastConversationInitEvent(ctx context.Context, client *cloudfirestore.Client, payload map[string]any) {
	agentID, _ := payload["agent_id"].(string)
	agentID = strings.TrimSpace(agentID)
	if agentID == "" {
		return
	}
	docID := "agent_" + agentID

	cctx, cancel := context.WithTimeout(ctx, 800*time.Millisecond)
	defer cancel()

	_, err := client.Collection(agentWebhookEventsCollection).Doc(docID).Set(cctx, payload, cloudfirestore.MergeAll)
	if err != nil {
		// Don't break the webhook path if logging fails.
		log.Printf("conversation-init: failed to store last event agent=%s err=%v", agentID, err)
	}
}

func maskPhone(p string) string {
	p = agentcontext.NormalizePhoneNumber(p)
	if len(p) <= 6 {
		return p
	}
	return p[:3] + "…" + p[len(p)-3:]
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing response: %v", err)
	}
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

func getString(m map[string]any, key string) string {
	v, ok := m[key]
	if !ok {
		return ""
	}
	return anyToString(v)
}

func getStringNested(m map[string]any, parentKey string, childKey string) string {
	v, ok := m[parentKey]
	if !ok {
		return ""
	}
	asMap, ok := v.(map[string]any)
	if !ok {
		return ""
	}
	return getString(asMap, childKey)
}

func anyToString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
	}
}

func orNull(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}
