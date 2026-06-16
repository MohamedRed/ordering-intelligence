package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type ctxKey string

const authContextKey ctxKey = "auth_ctx"

type oauthTokenCache struct {
	mu        sync.Mutex
	token     string
	expiresAt time.Time
}

var uberTokenCache oauthTokenCache
var stuartTokenCache oauthTokenCache

const (
	defaultPort = "8080"

	ordersCollection     = "orders"
	storesCollection     = "stores"
	deliveriesCollection = "deliveries"
)

type serviceConfig struct {
	Port               string
	Environment        string
	FirestoreProjectID string
	CredentialsFile    string
	RequireAuth        bool
	CORSOrigins        []string

	InternalAuthAudience  string
	InternalAllowedEmails []string

	OrderServiceURL        string
	DispatchServiceURL     string
	OrdersEventsAudience   string
	DeliveriesEventsTopic  string
	ProviderMode           string
	UberDirectAPIKey       string
	UberDirectClientID     string
	UberDirectClientSecret string
	UberDirectCustomerID   string
	UberDirectAccessToken  string
	UberDirectAuthURL      string
	UberDirectAPIBaseURL   string
	StuartAPIKey           string
	StuartClientID         string
	StuartClientSecret     string
	StuartAccessToken      string
	StuartAPIBaseURL       string
}

type authContext struct {
	UID      string
	Role     string
	StoreIDs []string
}

type tokenVerifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (*auth.Token, error)
}

type pubsubPushEnvelope struct {
	Message struct {
		Data      string            `json:"data"`
		MessageID string            `json:"messageId"`
		Attrs     map[string]string `json:"attributes"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type deliveryLatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type deliveryAddress struct {
	Line1      string `json:"line1,omitempty"`
	Line2      string `json:"line2,omitempty"`
	City       string `json:"city,omitempty"`
	State      string `json:"state,omitempty"`
	PostalCode string `json:"postalCode,omitempty"`
	Country    string `json:"country,omitempty"`
	Formatted  string `json:"formatted,omitempty"`
}

type deliveryQuote struct {
	Provider            string `json:"provider"`
	ProviderFeeCents    int64  `json:"providerFeeCents"`
	DropoffEtaMinutes   int64  `json:"dropoffEtaMinutes"`
	QuoteExpiresAt      string `json:"quoteExpiresAt"`
	Currency            string `json:"currency"`
	ProviderDisplayName string `json:"providerDisplayName,omitempty"`
}

type deliveryQuotePayload struct {
	Provider      string           `json:"provider,omitempty"`
	DropoffLatLng *deliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddr   *deliveryAddress `json:"dropoffAddress,omitempty"`
}

type orderDelivery struct {
	FleetMode             string           `json:"fleetMode,omitempty"`
	DropoffLatLng         *deliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress        *deliveryAddress `json:"dropoffAddress,omitempty"`
	Instructions          string           `json:"instructions,omitempty"`
	Quote                 *deliveryQuote   `json:"quote,omitempty"`
	OfferCents            int64            `json:"offerCents,omitempty"`
	ProviderDeliveryID    string           `json:"providerDeliveryId,omitempty"`
	TrackingURL           string           `json:"trackingUrl,omitempty"`
	DeliveryStatusSummary string           `json:"deliveryStatusSummary,omitempty"`
}

type orderRecord struct {
	ID              string         `json:"id"`
	StoreID         string         `json:"storeId"`
	Status          string         `json:"status"`
	FulfillmentType string         `json:"fulfillmentType"`
	Delivery        *orderDelivery `json:"delivery,omitempty"`
	CreatedAt       time.Time      `json:"createdAt"`
}

type deliveryRecord struct {
	DeliveryID         string         `json:"deliveryId" firestore:"deliveryId"`
	OrderID            string         `json:"orderId" firestore:"orderId"`
	StoreID            string         `json:"storeId" firestore:"storeId"`
	Provider           string         `json:"provider" firestore:"provider"`
	ProviderDeliveryID string         `json:"providerDeliveryId" firestore:"providerDeliveryId"`
	TrackingURL        string         `json:"trackingUrl" firestore:"trackingUrl"`
	Status             string         `json:"status" firestore:"status"`
	Payload            map[string]any `json:"payload,omitempty" firestore:"payload,omitempty"`
	CreatedAt          time.Time      `json:"createdAt" firestore:"createdAt"`
	UpdatedAt          time.Time      `json:"updatedAt" firestore:"updatedAt"`
}

type deliveryEvent struct {
	Kind       string         `json:"kind"`
	StoreID    string         `json:"storeId"`
	OrderID    string         `json:"orderId,omitempty"`
	DeliveryID string         `json:"deliveryId,omitempty"`
	Provider   string         `json:"provider,omitempty"`
	Status     string         `json:"status,omitempty"`
	CreatedAt  string         `json:"createdAt"`
	Payload    map[string]any `json:"payload,omitempty"`
}

type storeDeliverySettings struct {
	FleetMode             string
	ProviderSelectionMode string
	PrimaryProvider       string
	EnabledProviders      []string
	RoutingPolicy         deliveryRoutingPolicy
}

type deliveryRoutingPolicy struct {
	OptimizeFor         string
	MaxEtaMinutes       int64
	MaxProviderFeeCents int64
	MaxQuoteLatencyMs   int64
}

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed loading config: %v", err)
	}

	ctx := context.Background()
	fs, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer fs.Close()

	var authClient *auth.Client
	if cfg.RequireAuth {
		authClient, err = newFirebaseAuthClient(ctx, cfg)
		if err != nil {
			log.Fatalf("failed to create firebase auth client: %v", err)
		}
	}

	pubsubClient, err := cloudpubsub.NewClient(ctx, cfg.FirestoreProjectID)
	if err != nil {
		log.Printf("pubsub client not initialised: %v", err)
		pubsubClient = nil
	}
	defer func() {
		if pubsubClient != nil {
			_ = pubsubClient.Close()
		}
	}()

	httpClient := &http.Client{Timeout: 20 * time.Second}
	var orderTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.OrderServiceURL) != "" {
		ts, err := idtoken.NewTokenSource(ctx, cfg.OrderServiceURL)
		if err != nil {
			log.Printf("order-service token source not initialised: %v", err)
		} else {
			orderTokenSrc = ts
		}
	}
	var dispatchTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.DispatchServiceURL) != "" {
		ts, err := idtoken.NewTokenSource(ctx, cfg.DispatchServiceURL)
		if err != nil {
			log.Printf("dispatch-service token source not initialised: %v", err)
		} else {
			dispatchTokenSrc = ts
		}
	}

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.RealIP)
	router.Use(middleware.Recoverer)
	router.Use(deliveryCORSMiddleware(cfg.CORSOrigins))

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "delivery-service"})
	})

	router.Route("/v1", func(r chi.Router) {
		if cfg.RequireAuth {
			r.Use(firebaseOrInternalMiddleware(authClient, cfg.InternalAuthAudience, cfg.InternalAllowedEmails))
		}

		r.Post("/stores/{storeID}/delivery/quote", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !canAccessStore(r.Context(), storeID) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			quoteDelivery(w, r, fs, cfg, httpClient, dispatchTokenSrc, storeID)
		})

		r.Post("/orders/{orderID}/delivery/dispatch", func(w http.ResponseWriter, r *http.Request) {
			orderID := strings.TrimSpace(chi.URLParam(r, "orderID"))
			if orderID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
				return
			}
			dispatchDelivery(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc, orderID)
		})
	})

	router.Route("/tasks", func(r chi.Router) {
		r.Post("/orders-events", func(w http.ResponseWriter, r *http.Request) {
			handleOrdersEvents(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc)
		})
		r.Post("/providers/{provider}/webhook", func(w http.ResponseWriter, r *http.Request) {
			provider := strings.TrimSpace(chi.URLParam(r, "provider"))
			handleProviderWebhook(w, r, fs, cfg, pubsubClient, httpClient, orderTokenSrc, provider)
		})
	})

	log.Printf("delivery-service listening on :%s", cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, router))
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("delivery-service", nil)
	if err != nil {
		return nil, err
	}

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = defaultPort
	}

	project := strings.TrimSpace(stringOrDefault(values["FIRESTORE_PROJECT_ID"], strings.TrimSpace(os.Getenv("FIRESTORE_PROJECT_ID"))))
	if project == "" {
		project = strings.TrimSpace(os.Getenv("GOOGLE_CLOUD_PROJECT"))
	}
	if project == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}

	internalAllowed := strings.TrimSpace(stringOrDefault(values["INTERNAL_ALLOWED_EMAILS"], strings.TrimSpace(os.Getenv("INTERNAL_ALLOWED_EMAILS"))))
	internalAllowedEmails := splitCSV(internalAllowed)
	corsOrigins, err := resolveDeliveryCORSOrigins(
		strings.TrimSpace(stringOrDefault(values["CORS_ORIGINS"], strings.TrimSpace(os.Getenv("CORS_ORIGINS")))),
	)
	if err != nil {
		return nil, err
	}

	providerMode := strings.ToLower(strings.TrimSpace(stringOrDefault(values["PROVIDER_MODE"], strings.TrimSpace(os.Getenv("PROVIDER_MODE")))))
	if providerMode == "" {
		providerMode = "mock"
	}

	uberBase := strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_API_BASE_URL"], strings.TrimSpace(os.Getenv("UBER_DIRECT_API_BASE_URL"))))
	if uberBase == "" {
		uberBase = "https://api.uber.com/v1"
	}
	uberAuth := strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_AUTH_URL"], strings.TrimSpace(os.Getenv("UBER_DIRECT_AUTH_URL"))))
	if uberAuth == "" {
		uberAuth = "https://auth.uber.com/oauth/v2/token"
	}

	stuartBase := strings.TrimSpace(stringOrDefault(values["STUART_API_BASE_URL"], strings.TrimSpace(os.Getenv("STUART_API_BASE_URL"))))
	if stuartBase == "" {
		stuartBase = "https://api.stuart.com"
	}

	return &serviceConfig{
		Port:                   port,
		Environment:            strings.TrimSpace(stringOrDefault(values["ENVIRONMENT"], "development")),
		FirestoreProjectID:     project,
		CredentialsFile:        strings.TrimSpace(stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], "")),
		RequireAuth:            strings.TrimSpace(stringOrDefault(values["REQUIRE_AUTH"], strings.TrimSpace(os.Getenv("REQUIRE_AUTH")))) != "false",
		CORSOrigins:            corsOrigins,
		InternalAuthAudience:   strings.TrimSpace(stringOrDefault(values["INTERNAL_AUTH_AUDIENCE"], strings.TrimSpace(os.Getenv("INTERNAL_AUTH_AUDIENCE")))),
		InternalAllowedEmails:  internalAllowedEmails,
		OrderServiceURL:        strings.TrimSpace(stringOrDefault(values["ORDER_SERVICE_URL"], strings.TrimSpace(os.Getenv("ORDER_SERVICE_URL")))),
		DispatchServiceURL:     strings.TrimSpace(stringOrDefault(values["DISPATCH_SERVICE_URL"], strings.TrimSpace(os.Getenv("DISPATCH_SERVICE_URL")))),
		OrdersEventsAudience:   strings.TrimSpace(stringOrDefault(values["ORDERS_EVENTS_OIDC_AUDIENCE"], strings.TrimSpace(os.Getenv("ORDERS_EVENTS_OIDC_AUDIENCE")))),
		DeliveriesEventsTopic:  strings.TrimSpace(stringOrDefault(values["DELIVERIES_EVENTS_TOPIC"], strings.TrimSpace(os.Getenv("DELIVERIES_EVENTS_TOPIC")))),
		ProviderMode:           providerMode,
		UberDirectAPIKey:       strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_API_KEY"], strings.TrimSpace(os.Getenv("UBER_DIRECT_API_KEY")))),
		UberDirectClientID:     strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_CLIENT_ID"], strings.TrimSpace(os.Getenv("UBER_DIRECT_CLIENT_ID")))),
		UberDirectClientSecret: strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_CLIENT_SECRET"], strings.TrimSpace(os.Getenv("UBER_DIRECT_CLIENT_SECRET")))),
		UberDirectCustomerID:   strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_CUSTOMER_ID"], strings.TrimSpace(os.Getenv("UBER_DIRECT_CUSTOMER_ID")))),
		UberDirectAccessToken:  strings.TrimSpace(stringOrDefault(values["UBER_DIRECT_ACCESS_TOKEN"], strings.TrimSpace(os.Getenv("UBER_DIRECT_ACCESS_TOKEN")))),
		UberDirectAuthURL:      uberAuth,
		UberDirectAPIBaseURL:   strings.TrimRight(uberBase, "/"),
		StuartAPIKey:           strings.TrimSpace(stringOrDefault(values["STUART_API_KEY"], strings.TrimSpace(os.Getenv("STUART_API_KEY")))),
		StuartClientID:         strings.TrimSpace(stringOrDefault(values["STUART_CLIENT_ID"], strings.TrimSpace(os.Getenv("STUART_CLIENT_ID")))),
		StuartClientSecret:     strings.TrimSpace(stringOrDefault(values["STUART_CLIENT_SECRET"], strings.TrimSpace(os.Getenv("STUART_CLIENT_SECRET")))),
		StuartAccessToken:      strings.TrimSpace(stringOrDefault(values["STUART_ACCESS_TOKEN"], strings.TrimSpace(os.Getenv("STUART_ACCESS_TOKEN")))),
		StuartAPIBaseURL:       strings.TrimRight(stuartBase, "/"),
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	var opts []option.ClientOption
	if strings.TrimSpace(cfg.CredentialsFile) != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}
	return cloudfirestore.NewClient(ctx, cfg.FirestoreProjectID, opts...)
}

func newFirebaseAuthClient(ctx context.Context, cfg *serviceConfig) (*auth.Client, error) {
	var opts []option.ClientOption
	if strings.TrimSpace(cfg.CredentialsFile) != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: cfg.FirestoreProjectID}, opts...)
	if err != nil {
		return nil, err
	}
	return app.Auth(ctx)
}

func firebaseOrInternalMiddleware(authClient tokenVerifier, audience string, allowedEmails []string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if authClient == nil {
				next.ServeHTTP(w, r)
				return
			}
			authHeader := r.Header.Get("Authorization")
			if strings.TrimSpace(authHeader) == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			if tokenString == authHeader {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}

			// Try Firebase auth first.
			if authClient != nil {
				if token, err := authClient.VerifyIDToken(r.Context(), tokenString); err == nil {
					storeIDs := extractStoreIDs(token)
					ctx := context.WithValue(r.Context(), authContextKey, authContext{UID: token.UID, Role: toString(token.Claims["role"]), StoreIDs: storeIDs})
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}

			// Internal IAM-style auth.
			if ok, ac := tryGoogleIDTokenAuth(r.Context(), tokenString, audience, allowedEmails); ok {
				ctx := context.WithValue(r.Context(), authContextKey, ac)
				next.ServeHTTP(w, r.WithContext(ctx))
				return
			}

			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		})
	}
}

func tryGoogleIDTokenAuth(ctx context.Context, tokenString, audience string, allowedEmails []string) (bool, authContext) {
	if audience == "" {
		return false, authContext{}
	}
	payload, err := idtoken.Validate(ctx, tokenString, audience)
	if err != nil {
		return false, authContext{}
	}
	email, _ := payload.Claims["email"].(string)
	if email == "" {
		return false, authContext{}
	}
	if len(allowedEmails) > 0 {
		ok := false
		for _, allowed := range allowedEmails {
			if strings.EqualFold(strings.TrimSpace(allowed), email) {
				ok = true
				break
			}
		}
		if !ok {
			return false, authContext{}
		}
	}
	return true, authContext{UID: email, Role: "internal", StoreIDs: []string{}}
}

func extractStoreIDs(token *auth.Token) []string {
	if token == nil {
		return nil
	}
	claims, ok := token.Claims["storeIds"]
	if !ok {
		return nil
	}
	list := []string{}
	switch v := claims.(type) {
	case []any:
		for _, item := range v {
			if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
				list = append(list, strings.TrimSpace(s))
			}
		}
	case []string:
		for _, s := range v {
			if strings.TrimSpace(s) != "" {
				list = append(list, strings.TrimSpace(s))
			}
		}
	}
	return list
}

func authUID(ctx context.Context) string {
	ac, ok := ctx.Value(authContextKey).(authContext)
	if !ok {
		return ""
	}
	return ac.UID
}

func canAccessStore(ctx context.Context, storeID string) bool {
	ac, ok := ctx.Value(authContextKey).(authContext)
	if !ok {
		return false
	}
	if len(ac.StoreIDs) == 0 {
		return true
	}
	for _, s := range ac.StoreIDs {
		if s == storeID {
			return true
		}
	}
	return false
}

func quoteDelivery(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	httpClient *http.Client,
	dispatchTokenSrc oauth2.TokenSource,
	storeID string,
) {
	var payload deliveryQuotePayload
	_ = json.NewDecoder(r.Body).Decode(&payload)

	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()

	settings, _ := fetchStoreDeliverySettings(ctx, fs, storeID)
	candidates, mode := resolveQuoteCandidates(strings.TrimSpace(payload.Provider), settings)

	if settings != nil && strings.ToLower(strings.TrimSpace(settings.FleetMode)) == "owned_fleet" && strings.TrimSpace(payload.Provider) == "" {
		if httpClient == nil || dispatchTokenSrc == nil || strings.TrimSpace(cfg.DispatchServiceURL) == "" {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "dispatch_service_not_configured"})
			return
		}
		status, contentType, body, err := quoteOwnedFleetViaDispatch(ctx, httpClient, dispatchTokenSrc, cfg.DispatchServiceURL, storeID, payload)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "dispatch_service_error"})
			return
		}
		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
		return
	}

	quotes := make([]deliveryQuote, 0, len(candidates))
	if cfg.ProviderMode == "mock" {
		for _, provider := range candidates {
			quotes = append(quotes, mockProviderQuote(provider))
		}
	} else {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		defer cancel()
		storeInfo, err := fetchStoreInfo(ctx, fs, storeID)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "store_fetch_failed"})
			return
		}
		for _, provider := range candidates {
			switch provider {
			case "uber_direct":
				quote, err := uberQuote(ctx, httpClient, cfg, storeInfo, payload)
				if err != nil {
					log.Printf("uber quote failed: %v", err)
					continue
				}
				quotes = append(quotes, quote)
			case "stuart":
				quote, err := stuartQuote(ctx, httpClient, cfg, storeInfo, payload)
				if err != nil {
					log.Printf("stuart quote failed: %v", err)
					continue
				}
				quotes = append(quotes, quote)
			default:
				log.Printf("unsupported provider: %s", provider)
			}
		}
	}

	if len(quotes) == 0 {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "quote_failed"})
		return
	}

	selected := selectQuote(quotes, mode, settings)
	writeJSON(w, http.StatusOK, selected)
}

func fetchStoreDeliverySettings(ctx context.Context, fs *cloudfirestore.Client, storeID string) (*storeDeliverySettings, error) {
	if fs == nil {
		return nil, nil
	}
	snap, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	raw := snap.Data()
	ds, _ := raw["delivery_settings"].(map[string]any)
	if ds == nil {
		if alt, ok := raw["deliverySettings"].(map[string]any); ok {
			ds = alt
		}
	}
	if ds == nil {
		return nil, nil
	}

	settings := &storeDeliverySettings{
		FleetMode:             strings.ToLower(strings.TrimSpace(firstNonEmpty(toString(ds["fleet_mode"]), toString(ds["fleetMode"])))),
		ProviderSelectionMode: strings.ToLower(strings.TrimSpace(toString(ds["provider_selection_mode"]))),
		PrimaryProvider:       normalizeProvider(toString(ds["primary_provider"])),
		EnabledProviders:      normalizeProviders(toStringSlice(ds["enabled_providers"])),
		RoutingPolicy: deliveryRoutingPolicy{
			OptimizeFor:         strings.ToLower(strings.TrimSpace(toString(ds["optimize_for"]))),
			MaxEtaMinutes:       toInt64(ds["max_eta_minutes"]),
			MaxProviderFeeCents: toInt64(ds["max_provider_fee_cents"]),
			MaxQuoteLatencyMs:   toInt64(ds["max_quote_latency_ms"]),
		},
	}

	if rp, ok := ds["routing_policy"].(map[string]any); ok {
		if settings.RoutingPolicy.OptimizeFor == "" {
			settings.RoutingPolicy.OptimizeFor = strings.ToLower(strings.TrimSpace(toString(rp["optimize_for"])))
		}
		if settings.RoutingPolicy.MaxEtaMinutes == 0 {
			settings.RoutingPolicy.MaxEtaMinutes = toInt64(rp["max_eta_minutes"])
		}
		if settings.RoutingPolicy.MaxProviderFeeCents == 0 {
			settings.RoutingPolicy.MaxProviderFeeCents = toInt64(rp["max_provider_fee_cents"])
		}
		if settings.RoutingPolicy.MaxQuoteLatencyMs == 0 {
			settings.RoutingPolicy.MaxQuoteLatencyMs = toInt64(rp["max_quote_latency_ms"])
		}
	}

	return settings, nil
}

func resolveQuoteCandidates(providerOverride string, settings *storeDeliverySettings) ([]string, string) {
	if providerOverride != "" {
		return []string{normalizeProvider(providerOverride)}, "single"
	}
	if settings != nil {
		mode := strings.ToLower(strings.TrimSpace(settings.ProviderSelectionMode))
		switch mode {
		case "auto":
			candidates := normalizeProviders(settings.EnabledProviders)
			if len(candidates) > 0 {
				return candidates, "auto"
			}
		case "single":
			// fallthrough to primary provider
		}
		if settings.PrimaryProvider != "" {
			return []string{normalizeProvider(settings.PrimaryProvider)}, "single"
		}
	}
	return []string{"mock"}, "single"
}

func selectQuote(quotes []deliveryQuote, mode string, settings *storeDeliverySettings) deliveryQuote {
	if len(quotes) == 0 {
		return mockProviderQuote("mock")
	}
	if mode != "auto" || len(quotes) == 1 {
		return quotes[0]
	}

	policy := deliveryRoutingPolicy{OptimizeFor: "eta"}
	primary := ""
	if settings != nil {
		if settings.RoutingPolicy.OptimizeFor != "" {
			policy.OptimizeFor = settings.RoutingPolicy.OptimizeFor
		}
		if settings.RoutingPolicy.MaxEtaMinutes > 0 {
			policy.MaxEtaMinutes = settings.RoutingPolicy.MaxEtaMinutes
		}
		if settings.RoutingPolicy.MaxProviderFeeCents > 0 {
			policy.MaxProviderFeeCents = settings.RoutingPolicy.MaxProviderFeeCents
		}
		primary = settings.PrimaryProvider
	}

	filtered := make([]deliveryQuote, 0, len(quotes))
	for _, q := range quotes {
		if policy.MaxEtaMinutes > 0 && q.DropoffEtaMinutes > policy.MaxEtaMinutes {
			continue
		}
		if policy.MaxProviderFeeCents > 0 && q.ProviderFeeCents > policy.MaxProviderFeeCents {
			continue
		}
		filtered = append(filtered, q)
	}
	if len(filtered) == 0 {
		filtered = quotes
	}

	best := filtered[0]
	bestScore := scoreQuote(best, policy)
	for _, q := range filtered[1:] {
		score := scoreQuote(q, policy)
		if score < bestScore {
			best = q
			bestScore = score
			continue
		}
		if score == bestScore && primary != "" && q.Provider == primary {
			best = q
			bestScore = score
		}
	}
	return best
}

func scoreQuote(q deliveryQuote, policy deliveryRoutingPolicy) float64 {
	switch strings.ToLower(strings.TrimSpace(policy.OptimizeFor)) {
	case "cost":
		return float64(q.ProviderFeeCents)
	case "balanced":
		return float64(q.DropoffEtaMinutes) + (float64(q.ProviderFeeCents) / 100.0)
	default:
		return float64(q.DropoffEtaMinutes)
	}
}

func mockProviderQuote(provider string) deliveryQuote {
	provider = normalizeProvider(provider)
	fee := int64(699)
	eta := int64(25)
	display := ""
	switch provider {
	case "uber_direct":
		fee = 799
		eta = 22
		display = "Uber Direct"
	case "stuart":
		fee = 699
		eta = 27
		display = "Stuart"
	case "mock":
		display = "Mock Courier"
	default:
		display = strings.ReplaceAll(provider, "_", " ")
	}
	return deliveryQuote{
		Provider:            provider,
		ProviderFeeCents:    fee,
		DropoffEtaMinutes:   eta,
		QuoteExpiresAt:      time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
		Currency:            "USD",
		ProviderDisplayName: display,
	}
}

type storeLocation struct {
	Lat       float64
	Lng       float64
	Formatted string
}

type storeInfo struct {
	StoreID  string
	Name     string
	Phone    string
	Location *storeLocation
}

func fetchStoreInfo(ctx context.Context, fs *cloudfirestore.Client, storeID string) (*storeInfo, error) {
	if fs == nil {
		return nil, fmt.Errorf("firestore_not_configured")
	}
	snap, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil {
		return nil, err
	}
	raw := snap.Data()
	name := strings.TrimSpace(toString(raw["name"]))
	phone := strings.TrimSpace(toString(raw["phone"]))
	if phone == "" {
		phone = strings.TrimSpace(toString(raw["twilio_number"]))
	}

	var loc *storeLocation
	ds, _ := raw["delivery_settings"].(map[string]any)
	if ds == nil {
		if alt, ok := raw["deliverySettings"].(map[string]any); ok {
			ds = alt
		}
	}
	if ds != nil {
		m, _ := ds["store_location"].(map[string]any)
		if m == nil {
			if alt, ok := ds["storeLocation"].(map[string]any); ok {
				m = alt
			}
		}
		if m != nil {
			loc = &storeLocation{
				Lat:       toFloat64(m["lat"]),
				Lng:       toFloat64(m["lng"]),
				Formatted: strings.TrimSpace(toString(m["formatted"])),
			}
		}
	}
	if loc == nil {
		return nil, fmt.Errorf("missing_store_location")
	}
	return &storeInfo{
		StoreID:  storeID,
		Name:     name,
		Phone:    phone,
		Location: loc,
	}, nil
}

func uberQuote(ctx context.Context, client *http.Client, cfg *serviceConfig, store *storeInfo, payload deliveryQuotePayload) (deliveryQuote, error) {
	if store == nil || store.Location == nil {
		return deliveryQuote{}, fmt.Errorf("missing_store_location")
	}
	pickupAddr, err := uberAddressJSON(nil, firstNonEmpty(store.Location.Formatted, latLngFallback(store.Location.Lat, store.Location.Lng)))
	if err != nil {
		return deliveryQuote{}, err
	}
	dropoffAddr, err := uberAddressJSON(payload.DropoffAddr, latLngFallback(latLngFrom(payload.DropoffLatLng)))
	if err != nil {
		return deliveryQuote{}, err
	}
	body := map[string]any{
		"pickup_address":  pickupAddr,
		"dropoff_address": dropoffAddr,
	}
	if strings.TrimSpace(store.StoreID) != "" {
		body["external_store_id"] = strings.TrimSpace(store.StoreID)
	}
	if store.Location.Lat != 0 && store.Location.Lng != 0 {
		body["pickup_latitude"] = store.Location.Lat
		body["pickup_longitude"] = store.Location.Lng
	}
	if payload.DropoffLatLng != nil && payload.DropoffLatLng.Lat != 0 && payload.DropoffLatLng.Lng != 0 {
		body["dropoff_latitude"] = payload.DropoffLatLng.Lat
		body["dropoff_longitude"] = payload.DropoffLatLng.Lng
	}

	resp, err := uberDo(ctx, client, cfg, http.MethodPost, "/customers/"+url.PathEscape(cfg.UberDirectCustomerID)+"/delivery_quotes", body)
	if err != nil {
		return deliveryQuote{}, err
	}
	fee := toInt64(resp["fee"])
	duration := toInt64(resp["duration"])
	currency := strings.ToUpper(strings.TrimSpace(toString(resp["currency_type"])))
	if currency == "" {
		currency = strings.ToUpper(strings.TrimSpace(toString(resp["currency"])))
	}
	expires := strings.TrimSpace(toString(resp["expires"]))
	if expires == "" {
		expires = time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339)
	}
	return deliveryQuote{
		Provider:            "uber_direct",
		ProviderFeeCents:    fee,
		DropoffEtaMinutes:   duration,
		QuoteExpiresAt:      expires,
		Currency:            currency,
		ProviderDisplayName: "Uber Direct",
	}, nil
}

func uberCreateDelivery(ctx context.Context, client *http.Client, cfg *serviceConfig, store *storeInfo, order map[string]any, delivery *orderDelivery) (string, string, string, error) {
	if store == nil || store.Location == nil {
		return "", "", "", fmt.Errorf("missing_store_location")
	}
	if delivery == nil {
		delivery = &orderDelivery{}
	}
	customerName := strings.TrimSpace(toString(order["customerName"]))
	if customerName == "" {
		customerName = "Customer"
	}
	customerPhone := strings.TrimSpace(toString(order["callerId"]))
	dropoffAddr, err := uberAddressJSON(delivery.DropoffAddress, latLngFallback(latLngFrom(delivery.DropoffLatLng)))
	if err != nil {
		return "", "", "", err
	}
	pickupAddr, err := uberAddressJSON(nil, firstNonEmpty(store.Location.Formatted, latLngFallback(store.Location.Lat, store.Location.Lng)))
	if err != nil {
		return "", "", "", err
	}
	manifestItems, manifestTotal := buildUberManifest(order)
	if len(manifestItems) == 0 {
		manifestItems = []map[string]any{{"name": "Order", "quantity": 1, "size": "medium"}}
	}
	body := map[string]any{
		"pickup_name":          firstNonEmpty(store.Name, "Store"),
		"pickup_address":       pickupAddr,
		"pickup_phone_number":  firstNonEmpty(store.Phone, customerPhone),
		"dropoff_name":         customerName,
		"dropoff_address":      dropoffAddr,
		"dropoff_phone_number": customerPhone,
		"manifest_items":       manifestItems,
		"manifest_reference":   toString(order["id"]),
		"external_id":          toString(order["id"]),
	}
	if strings.TrimSpace(store.StoreID) != "" {
		body["external_store_id"] = strings.TrimSpace(store.StoreID)
	}
	if strings.TrimSpace(store.Name) != "" {
		body["pickup_business_name"] = strings.TrimSpace(store.Name)
	}
	if manifestTotal > 0 {
		body["manifest_total_value"] = manifestTotal
	}
	if delivery != nil && delivery.DropoffLatLng != nil {
		if delivery.DropoffLatLng.Lat != 0 && delivery.DropoffLatLng.Lng != 0 {
			body["dropoff_latitude"] = delivery.DropoffLatLng.Lat
			body["dropoff_longitude"] = delivery.DropoffLatLng.Lng
		}
	}
	if store.Location.Lat != 0 && store.Location.Lng != 0 {
		body["pickup_latitude"] = store.Location.Lat
		body["pickup_longitude"] = store.Location.Lng
	}
	if delivery != nil && strings.TrimSpace(delivery.Instructions) != "" {
		body["dropoff_notes"] = strings.TrimSpace(delivery.Instructions)
	}

	resp, err := uberDo(ctx, client, cfg, http.MethodPost, "/customers/"+url.PathEscape(cfg.UberDirectCustomerID)+"/deliveries", body)
	if err != nil {
		return "", "", "", err
	}
	providerDeliveryID := strings.TrimSpace(toString(resp["id"]))
	trackingURL := strings.TrimSpace(toString(resp["tracking_url"]))
	status := strings.TrimSpace(toString(resp["status"]))
	return providerDeliveryID, trackingURL, status, nil
}

func stuartQuote(ctx context.Context, client *http.Client, cfg *serviceConfig, store *storeInfo, payload deliveryQuotePayload) (deliveryQuote, error) {
	job := buildStuartJob(store, payload.DropoffAddr, payload.DropoffLatLng, "", "", "")
	etaResp, err := stuartDo(ctx, client, cfg, http.MethodPost, "/v2/jobs/eta", map[string]any{"job": job})
	if err != nil {
		return deliveryQuote{}, err
	}
	etaSeconds := toInt64(etaResp["eta"])
	cptResp, _ := stuartDo(ctx, client, cfg, http.MethodPost, "/v2/jobs/cpt", map[string]any{"job": job})
	dropoffSeconds := toInt64(cptResp["cpt"])
	if dropoffSeconds == 0 {
		dropoffSeconds = etaSeconds
	}
	priceResp, _ := stuartDo(ctx, client, cfg, http.MethodPost, "/v2/jobs/pricing", map[string]any{"job": job})
	feeCents, currency := parseStuartPricing(priceResp)
	if feeCents == 0 {
		feeCents = 699
	}
	if currency == "" {
		currency = "USD"
	}
	return deliveryQuote{
		Provider:            "stuart",
		ProviderFeeCents:    feeCents,
		DropoffEtaMinutes:   secondsToMinutes(dropoffSeconds),
		QuoteExpiresAt:      time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
		Currency:            currency,
		ProviderDisplayName: "Stuart",
	}, nil
}

func stuartCreateDelivery(ctx context.Context, client *http.Client, cfg *serviceConfig, store *storeInfo, order map[string]any, delivery *orderDelivery) (string, string, string, error) {
	customerName := strings.TrimSpace(toString(order["customerName"]))
	customerPhone := strings.TrimSpace(toString(order["callerId"]))
	if delivery == nil {
		delivery = &orderDelivery{}
	}
	job := buildStuartJob(store, delivery.DropoffAddress, delivery.DropoffLatLng, customerName, customerPhone, strings.TrimSpace(delivery.Instructions))
	resp, err := stuartDo(ctx, client, cfg, http.MethodPost, "/v2/jobs", map[string]any{"job": job})
	if err != nil {
		return "", "", "", err
	}
	providerDeliveryID := strings.TrimSpace(toString(resp["id"]))
	trackingURL := strings.TrimSpace(toString(resp["tracking_url"]))
	status := strings.TrimSpace(toString(resp["status"]))
	if trackingURL == "" {
		if deliveries, ok := resp["deliveries"].([]any); ok && len(deliveries) > 0 {
			if d, ok := deliveries[0].(map[string]any); ok {
				if trackingURL == "" {
					trackingURL = strings.TrimSpace(toString(d["tracking_url"]))
				}
			}
		}
	}
	return providerDeliveryID, trackingURL, status, nil
}

func buildStuartJob(store *storeInfo, dropoff *deliveryAddress, dropoffLatLng *deliveryLatLng, customerName, customerPhone, dropoffNotes string) map[string]any {
	pickupAddress := formatAddressLine(nil, store.Location.Formatted)
	if pickupAddress == "" {
		pickupAddress = latLngFallback(store.Location.Lat, store.Location.Lng)
	}
	dropoffAddress := formatAddressLine(dropoff, "")
	if dropoffAddress == "" {
		lat, lng := latLngFrom(dropoffLatLng)
		dropoffAddress = latLngFallback(lat, lng)
	}
	if dropoffAddress == "" {
		dropoffAddress = "Unknown"
	}
	first, last := splitName(customerName)
	job := map[string]any{
		"pickup_at": time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
		"pickups": []map[string]any{
			{
				"address": pickupAddress,
				"comment": "Pickup order",
				"contact": map[string]any{
					"firstname": "Store",
					"lastname":  "",
					"phone":     firstNonEmpty(store.Phone, customerPhone),
					"company":   firstNonEmpty(store.Name, "Store"),
				},
			},
		},
		"dropoffs": []map[string]any{
			{
				"package_type":        "medium",
				"package_description": "Order",
				"client_reference":    store.StoreID,
				"address":             dropoffAddress,
				"comment":             dropoffNotes,
				"contact": map[string]any{
					"firstname": firstNonEmpty(first, "Customer"),
					"lastname":  last,
					"phone":     customerPhone,
					"company":   "Customer",
				},
			},
		},
	}
	if store.Location.Lat != 0 && store.Location.Lng != 0 {
		(job["pickups"].([]map[string]any))[0]["coordinates"] = map[string]any{
			"lat":  store.Location.Lat,
			"long": store.Location.Lng,
		}
	}
	if dropoffLatLng != nil && dropoffLatLng.Lat != 0 && dropoffLatLng.Lng != 0 {
		(job["dropoffs"].([]map[string]any))[0]["coordinates"] = map[string]any{
			"lat":  dropoffLatLng.Lat,
			"long": dropoffLatLng.Lng,
		}
	}
	return job
}

func uberDo(ctx context.Context, client *http.Client, cfg *serviceConfig, method, path string, body any) (map[string]any, error) {
	if client == nil {
		return nil, fmt.Errorf("http_client_missing")
	}
	if cfg.UberDirectCustomerID == "" {
		return nil, fmt.Errorf("uber_customer_id_missing")
	}
	token, err := uberAccessToken(ctx, client, cfg)
	if err != nil {
		return nil, err
	}
	endpoint := strings.TrimRight(cfg.UberDirectAPIBaseURL, "/") + path
	payload, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("uber_status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	out := map[string]any{}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func stuartDo(ctx context.Context, client *http.Client, cfg *serviceConfig, method, path string, body any) (map[string]any, error) {
	if client == nil {
		return nil, fmt.Errorf("http_client_missing")
	}
	token, err := stuartAccessToken(ctx, client, cfg)
	if err != nil {
		return nil, err
	}
	endpoint := strings.TrimRight(cfg.StuartAPIBaseURL, "/") + path
	payload, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("stuart_status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	out := map[string]any{}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func uberAccessToken(ctx context.Context, client *http.Client, cfg *serviceConfig) (string, error) {
	if cfg.UberDirectAccessToken != "" {
		return cfg.UberDirectAccessToken, nil
	}
	if cfg.UberDirectAPIKey != "" && cfg.UberDirectClientID == "" {
		return cfg.UberDirectAPIKey, nil
	}
	cache := &uberTokenCache
	cache.mu.Lock()
	if cache.token != "" && time.Now().Before(cache.expiresAt.Add(-1*time.Minute)) {
		token := cache.token
		cache.mu.Unlock()
		return token, nil
	}
	cache.mu.Unlock()

	if cfg.UberDirectClientID == "" || cfg.UberDirectClientSecret == "" {
		return "", fmt.Errorf("uber_credentials_missing")
	}
	values := url.Values{}
	values.Set("grant_type", "client_credentials")
	values.Set("scope", "eats.deliveries")
	values.Set("client_id", cfg.UberDirectClientID)
	values.Set("client_secret", cfg.UberDirectClientSecret)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, cfg.UberDirectAuthURL, strings.NewReader(values.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("uber_token_status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var tokenResp struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	if tokenResp.AccessToken == "" {
		return "", fmt.Errorf("uber_token_missing")
	}
	cache.mu.Lock()
	cache.token = tokenResp.AccessToken
	cache.expiresAt = time.Now().Add(time.Duration(tokenResp.ExpiresIn) * time.Second)
	cache.mu.Unlock()
	return tokenResp.AccessToken, nil
}

func stuartAccessToken(ctx context.Context, client *http.Client, cfg *serviceConfig) (string, error) {
	if cfg.StuartAccessToken != "" {
		return cfg.StuartAccessToken, nil
	}
	if cfg.StuartAPIKey != "" && cfg.StuartClientID == "" {
		return cfg.StuartAPIKey, nil
	}
	cache := &stuartTokenCache
	cache.mu.Lock()
	if cache.token != "" && time.Now().Before(cache.expiresAt.Add(-1*time.Minute)) {
		token := cache.token
		cache.mu.Unlock()
		return token, nil
	}
	cache.mu.Unlock()

	if cfg.StuartClientID == "" || cfg.StuartClientSecret == "" {
		return "", fmt.Errorf("stuart_credentials_missing")
	}
	values := url.Values{}
	values.Set("grant_type", "client_credentials")
	values.Set("scope", "api")
	values.Set("client_id", cfg.StuartClientID)
	values.Set("client_secret", cfg.StuartClientSecret)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(cfg.StuartAPIBaseURL, "/")+"/oauth/token", strings.NewReader(values.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("stuart_token_status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var tokenResp struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	if tokenResp.AccessToken == "" {
		return "", fmt.Errorf("stuart_token_missing")
	}
	cache.mu.Lock()
	cache.token = tokenResp.AccessToken
	cache.expiresAt = time.Now().Add(time.Duration(tokenResp.ExpiresIn) * time.Second)
	cache.mu.Unlock()
	return tokenResp.AccessToken, nil
}

func uberAddressJSON(addr *deliveryAddress, formatted string) (string, error) {
	if addr == nil && strings.TrimSpace(formatted) == "" {
		return "", fmt.Errorf("address_missing")
	}
	payload := map[string]any{}
	street := []string{}
	if addr != nil {
		if strings.TrimSpace(addr.Line1) != "" {
			street = append(street, strings.TrimSpace(addr.Line1))
		}
		if strings.TrimSpace(addr.Line2) != "" {
			street = append(street, strings.TrimSpace(addr.Line2))
		}
		if addr.City != "" {
			payload["city"] = addr.City
		}
		if addr.State != "" {
			payload["state"] = addr.State
		}
		if addr.PostalCode != "" {
			payload["zip_code"] = addr.PostalCode
		}
		if addr.Country != "" {
			payload["country"] = addr.Country
		}
		if strings.TrimSpace(addr.Formatted) != "" && len(street) == 0 {
			street = append(street, strings.TrimSpace(addr.Formatted))
		}
	}
	if len(street) == 0 && strings.TrimSpace(formatted) != "" {
		street = append(street, strings.TrimSpace(formatted))
	}
	if len(street) == 0 {
		return "", fmt.Errorf("address_missing")
	}
	payload["street_address"] = street
	raw, _ := json.Marshal(payload)
	return string(raw), nil
}

func formatAddressLine(addr *deliveryAddress, formatted string) string {
	if addr != nil {
		parts := []string{}
		for _, p := range []string{addr.Line1, addr.Line2, addr.City, addr.State, addr.PostalCode, addr.Country} {
			if strings.TrimSpace(p) != "" {
				parts = append(parts, strings.TrimSpace(p))
			}
		}
		if len(parts) > 0 {
			return strings.Join(parts, ", ")
		}
		if strings.TrimSpace(addr.Formatted) != "" {
			return strings.TrimSpace(addr.Formatted)
		}
	}
	if strings.TrimSpace(formatted) != "" {
		return strings.TrimSpace(formatted)
	}
	return ""
}

func buildUberManifest(order map[string]any) ([]map[string]any, int64) {
	itemsRaw, _ := order["items"].([]any)
	out := []map[string]any{}
	var total int64
	for _, item := range itemsRaw {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		name := strings.TrimSpace(toString(m["name"]))
		if name == "" {
			name = "Item"
		}
		qty := toInt64(m["quantity"])
		if qty <= 0 {
			qty = 1
		}
		price := toInt64(m["priceCents"])
		if price <= 0 {
			price = toInt64(m["price"])
		}
		if price < 0 {
			price = 0
		}
		total += price * qty
		out = append(out, map[string]any{
			"name":     name,
			"quantity": qty,
			"price":    price,
			"size":     "medium",
		})
	}
	if total == 0 {
		total = toInt64(order["totalCents"])
	}
	return out, total
}

func parseStuartPricing(resp map[string]any) (int64, string) {
	if resp == nil {
		return 0, ""
	}
	if v := toInt64(resp["amount"]); v > 0 {
		return v, strings.ToUpper(strings.TrimSpace(toString(resp["currency"])))
	}
	if v := toInt64(resp["price"]); v > 0 {
		return v, strings.ToUpper(strings.TrimSpace(toString(resp["currency"])))
	}
	if pricing, ok := resp["pricing"].(map[string]any); ok {
		if v := toInt64(pricing["amount"]); v > 0 {
			return v, strings.ToUpper(strings.TrimSpace(toString(pricing["currency"])))
		}
		if v := toInt64(pricing["price"]); v > 0 {
			return v, strings.ToUpper(strings.TrimSpace(toString(pricing["currency"])))
		}
	}
	return 0, ""
}

func secondsToMinutes(seconds int64) int64 {
	if seconds <= 0 {
		return 0
	}
	return (seconds + 59) / 60
}

func splitName(name string) (string, string) {
	parts := strings.Fields(strings.TrimSpace(name))
	if len(parts) == 0 {
		return "", ""
	}
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.Join(parts[1:], " ")
}

func latLngFrom(point *deliveryLatLng) (float64, float64) {
	if point == nil {
		return 0, 0
	}
	return point.Lat, point.Lng
}

func latLngFallback(lat, lng float64) string {
	if lat == 0 || lng == 0 {
		return ""
	}
	return fmt.Sprintf("%.6f, %.6f", lat, lng)
}

func quoteOwnedFleetViaDispatch(
	ctx context.Context,
	httpClient *http.Client,
	tokenSrc oauth2.TokenSource,
	baseURL string,
	storeID string,
	payload any,
) (int, string, []byte, error) {
	if httpClient == nil || tokenSrc == nil {
		return http.StatusServiceUnavailable, "", nil, fmt.Errorf("dispatch_not_configured")
	}
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {
		return http.StatusServiceUnavailable, "", nil, fmt.Errorf("dispatch_not_configured")
	}
	body, _ := json.Marshal(payload)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/v1/stores/"+url.PathEscape(storeID)+"/quote", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if tok, err := tokenSrc.Token(); err == nil && tok != nil && tok.AccessToken != "" {
		req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return http.StatusBadGateway, "", nil, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header.Get("Content-Type"), respBody, nil
}

func normalizeProvider(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, " ", "_")
	return value
}

func normalizeProviderStatus(provider, status string) string {
	raw := strings.ToLower(strings.TrimSpace(status))
	switch provider {
	case "uber_direct":
		switch raw {
		case "pending":
			return "dispatched"
		case "pickup":
			return "delivery_assigned"
		case "pickup_complete":
			return "picked_up"
		case "dropoff":
			return "out_for_delivery"
		case "delivered":
			return "delivered"
		case "canceled", "cancelled", "returned":
			return "delivery_failed"
		default:
			return raw
		}
	case "stuart":
		switch raw {
		case "new", "scheduled", "searching", "accepted":
			return "dispatched"
		case "in_progress", "en_route", "delivering":
			return "out_for_delivery"
		case "completed", "finished", "delivered":
			return "delivered"
		case "canceled", "cancelled", "failed", "expired":
			return "delivery_failed"
		default:
			return raw
		}
	default:
		return raw
	}
}

func normalizeProviders(values []string) []string {
	out := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, v := range values {
		n := normalizeProvider(v)
		if n == "" || seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

func toStringSlice(value any) []string {
	switch v := value.(type) {
	case []string:
		return v
	case []any:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
				out = append(out, strings.TrimSpace(s))
			}
		}
		return out
	default:
		return nil
	}
}

func toInt64(value any) int64 {
	switch v := value.(type) {
	case int64:
		return v
	case int:
		return int64(v)
	case float64:
		return int64(v)
	case json.Number:
		i, _ := v.Int64()
		return i
	case string:
		if strings.TrimSpace(v) == "" {
			return 0
		}
		if i, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64); err == nil {
			return i
		}
	}
	return 0
}

func toFloat64(value any) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case float32:
		return float64(v)
	case int:
		return float64(v)
	case int64:
		return float64(v)
	case json.Number:
		f, _ := v.Float64()
		return f
	case string:
		if strings.TrimSpace(v) == "" {
			return 0
		}
		if f, err := strconv.ParseFloat(strings.TrimSpace(v), 64); err == nil {
			return f
		}
	}
	return 0
}

func dispatchDelivery(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	orderID string,
) {
	var payload struct {
		StoreID  string `json:"storeId"`
		Provider string `json:"provider"`
	}
	_ = json.NewDecoder(r.Body).Decode(&payload)

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	order, err := fetchOrder(ctx, fs, orderID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_fetch_failed"})
		return
	}
	if order == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "order_not_found"})
		return
	}
	orderRaw, _ := fetchOrderRaw(ctx, fs, orderID)
	storeID := strings.TrimSpace(order.StoreID)
	if storeID == "" {
		storeID = strings.TrimSpace(payload.StoreID)
	}
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if !canAccessStore(r.Context(), storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	if order.Delivery == nil || strings.ToLower(strings.TrimSpace(order.Delivery.FleetMode)) != "third_party" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "not_third_party_delivery"})
		return
	}
	if strings.TrimSpace(order.Delivery.ProviderDeliveryID) != "" {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":             "already_dispatched",
			"providerDeliveryId": order.Delivery.ProviderDeliveryID,
			"trackingUrl":        order.Delivery.TrackingURL,
		})
		return
	}

	provider := strings.TrimSpace(payload.Provider)
	if provider == "" && order.Delivery != nil && order.Delivery.Quote != nil {
		provider = strings.TrimSpace(order.Delivery.Quote.Provider)
	}
	if provider == "" {
		settings, _ := fetchStoreDeliverySettings(ctx, fs, storeID)
		if settings != nil {
			provider = strings.TrimSpace(settings.PrimaryProvider)
		}
	}
	if provider == "" {
		provider = "mock"
	}
	provider = normalizeProvider(provider)

	deliveryID := "del_" + sanitizeID(orderID)
	providerDeliveryID := ""
	trackingURL := ""
	status := "dispatched"

	if cfg.ProviderMode == "mock" || provider == "mock" {
		providerDeliveryID = "mock_" + sanitizeID(orderID)
		trackingURL = "https://tracking.mock/" + url.PathEscape(deliveryID)
	} else {
		storeInfo, err := fetchStoreInfo(ctx, fs, storeID)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "store_fetch_failed"})
			return
		}
		switch provider {
		case "uber_direct":
			id, tracking, pstatus, err := uberCreateDelivery(ctx, httpClient, cfg, storeInfo, orderRaw, order.Delivery)
			if err != nil {
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "provider_create_failed"})
				return
			}
			providerDeliveryID = id
			trackingURL = tracking
			status = normalizeProviderStatus(provider, pstatus)
		case "stuart":
			id, tracking, pstatus, err := stuartCreateDelivery(ctx, httpClient, cfg, storeInfo, orderRaw, order.Delivery)
			if err != nil {
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "provider_create_failed"})
				return
			}
			providerDeliveryID = id
			trackingURL = tracking
			status = normalizeProviderStatus(provider, pstatus)
		default:
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_provider"})
			return
		}
		if status == "" {
			status = "dispatched"
		}
	}

	delivery := deliveryRecord{
		DeliveryID:         deliveryID,
		OrderID:            orderID,
		StoreID:            storeID,
		Provider:           provider,
		ProviderDeliveryID: providerDeliveryID,
		TrackingURL:        trackingURL,
		Status:             status,
		CreatedAt:          time.Now().UTC(),
		UpdatedAt:          time.Now().UTC(),
	}

	if err := upsertDelivery(ctx, fs, storeID, deliveryID, delivery); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "delivery_write_failed"})
		return
	}

	_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, orderID, map[string]any{
		"providerDeliveryId":    providerDeliveryID,
		"trackingUrl":           trackingURL,
		"deliveryStatusSummary": status,
	})

	_ = publishDeliveryEvent(ctx, pubsubClient, cfg, deliveryEvent{
		Kind:       "delivery_dispatched",
		StoreID:    storeID,
		OrderID:    orderID,
		DeliveryID: deliveryID,
		Provider:   provider,
		Status:     status,
		CreatedAt:  time.Now().UTC().Format(time.RFC3339),
		Payload: map[string]any{
			"trackingUrl": trackingURL,
		},
	})

	writeJSON(w, http.StatusOK, map[string]any{
		"deliveryId":         deliveryID,
		"provider":           provider,
		"providerDeliveryId": providerDeliveryID,
		"trackingUrl":        trackingURL,
		"status":             status,
	})
}

func handleOrdersEvents(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
) {
	if cfg.OrdersEventsAudience != "" {
		ok := verifyGoogleOidc(r, cfg.OrdersEventsAudience)
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
	}

	var env pubsubPushEnvelope
	if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_message"})
		return
	}
	if env.Message.Data == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_message"})
		return
	}
	raw, err := base64.StdEncoding.DecodeString(env.Message.Data)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_message"})
		return
	}
	var order orderRecord
	if err := json.Unmarshal(raw, &order); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if order.ID == "" || order.StoreID == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}
	if order.Delivery == nil || strings.ToLower(strings.TrimSpace(order.Delivery.FleetMode)) != "third_party" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}
	if strings.TrimSpace(order.Delivery.ProviderDeliveryID) != "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "already_dispatched"})
		return
	}
	status := strings.ToLower(strings.TrimSpace(order.Status))
	if status != "confirmed" && status != "ready" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "waiting"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	if err := ensureDeliveryForOrder(ctx, fs, cfg, pubsubClient, httpClient, orderTokenSrc, order); err != nil {
		log.Printf("auto dispatch failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "dispatch_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "dispatched"})
}

type webhookUpdate struct {
	Provider           string
	ProviderDeliveryID string
	Status             string
	TrackingURL        string
	OrderID            string
	Payload            map[string]any
}

func handleProviderWebhook(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	provider string,
) {
	if fs == nil {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}
	provider = normalizeProvider(provider)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
		return
	}
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}

	update := extractWebhookUpdate(provider, payload)
	if update.ProviderDeliveryID == "" && update.OrderID == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	record, storeID, deliveryID := resolveDeliveryForWebhook(ctx, fs, provider, update)
	if storeID == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	}
	if update.OrderID == "" {
		update.OrderID = record.OrderID
	}
	if deliveryID == "" {
		deliveryID = record.DeliveryID
	}
	if deliveryID == "" && update.OrderID != "" {
		deliveryID = "del_" + sanitizeID(update.OrderID)
	}
	statusSummary := ""
	if update.Status != "" {
		statusSummary = normalizeProviderStatus(provider, update.Status)
	}
	if statusSummary == "" {
		statusSummary = record.Status
	}

	updated := record
	if updated.DeliveryID == "" {
		updated.DeliveryID = deliveryID
	}
	if update.ProviderDeliveryID != "" {
		updated.ProviderDeliveryID = update.ProviderDeliveryID
	}
	if update.TrackingURL != "" {
		updated.TrackingURL = update.TrackingURL
	}
	if statusSummary != "" {
		updated.Status = statusSummary
	}
	updated.Provider = firstNonEmpty(updated.Provider, provider)
	if updated.OrderID == "" {
		updated.OrderID = update.OrderID
	}
	if updated.StoreID == "" {
		updated.StoreID = storeID
	}
	updated.UpdatedAt = time.Now().UTC()
	if updated.CreatedAt.IsZero() {
		updated.CreatedAt = updated.UpdatedAt
	}
	updated.Payload = update.Payload
	if err := upsertDelivery(ctx, fs, storeID, deliveryID, updated); err != nil {
		log.Printf("webhook upsert failed: %v", err)
	}

	if update.OrderID != "" && statusSummary != "" {
		fields := map[string]any{
			"deliveryStatusSummary": statusSummary,
			"trackingUrl":           firstNonEmpty(update.TrackingURL, updated.TrackingURL),
		}
		if update.ProviderDeliveryID != "" {
			fields["providerDeliveryId"] = update.ProviderDeliveryID
		}
		_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, update.OrderID, fields)
	}

	if statusSummary != "" {
		_ = publishDeliveryEvent(ctx, pubsubClient, cfg, deliveryEvent{
			Kind:       statusSummary,
			StoreID:    storeID,
			OrderID:    update.OrderID,
			DeliveryID: deliveryID,
			Provider:   provider,
			Status:     statusSummary,
			CreatedAt:  time.Now().UTC().Format(time.RFC3339),
			Payload: map[string]any{
				"providerStatus": update.Status,
				"trackingUrl":    firstNonEmpty(update.TrackingURL, updated.TrackingURL),
			},
		})
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func extractWebhookUpdate(provider string, payload map[string]any) webhookUpdate {
	switch normalizeProvider(provider) {
	case "uber_direct":
		return extractUberWebhook(payload)
	case "stuart":
		return extractStuartWebhook(payload)
	default:
		return webhookUpdate{Provider: provider, Payload: payload}
	}
}

func extractUberWebhook(payload map[string]any) webhookUpdate {
	data, _ := payload["data"].(map[string]any)
	meta, _ := payload["meta"].(map[string]any)
	update := webhookUpdate{
		Provider: "uber_direct",
		Status:   strings.TrimSpace(toString(payload["status"])),
		Payload:  payload,
	}
	update.ProviderDeliveryID = firstNonEmpty(
		toString(payload["delivery_id"]),
		toString(data["id"]),
		toString(data["delivery_id"]),
		toString(meta["delivery_id"]),
		toString(meta["order_id"]),
	)
	if update.ProviderDeliveryID == "" {
		update.ProviderDeliveryID = extractIDFromURL(firstNonEmpty(toString(payload["resource_href"]), toString(meta["resource_href"])))
	}
	if update.Status == "" {
		update.Status = strings.TrimSpace(toString(meta["status"]))
	}
	update.TrackingURL = strings.TrimSpace(firstNonEmpty(
		toString(data["tracking_url"]),
		toString(payload["tracking_url"]),
	))
	update.OrderID = strings.TrimSpace(firstNonEmpty(
		toString(data["external_id"]),
		toString(data["manifest_reference"]),
		toString(meta["external_id"]),
		toString(meta["external_order_id"]),
	))
	return update
}

func extractStuartWebhook(payload map[string]any) webhookUpdate {
	job, _ := payload["job"].(map[string]any)
	if job == nil {
		job, _ = payload["data"].(map[string]any)
	}
	update := webhookUpdate{
		Provider: "stuart",
		Status:   strings.TrimSpace(toString(payload["status"])),
		Payload:  payload,
	}
	update.ProviderDeliveryID = firstNonEmpty(
		toString(payload["id"]),
		toString(payload["job_id"]),
		toString(job["id"]),
		toString(job["job_id"]),
	)
	if update.Status == "" {
		update.Status = strings.TrimSpace(firstNonEmpty(toString(job["status"]), toString(payload["state"])))
	}
	update.OrderID = strings.TrimSpace(firstNonEmpty(
		toString(payload["client_reference"]),
		toString(job["client_reference"]),
		toString(job["reference"]),
	))
	update.TrackingURL = strings.TrimSpace(firstNonEmpty(
		toString(payload["tracking_url"]),
		toString(job["tracking_url"]),
	))
	if update.TrackingURL == "" {
		if deliveries, ok := payload["deliveries"].([]any); ok && len(deliveries) > 0 {
			if d, ok := deliveries[0].(map[string]any); ok {
				update.TrackingURL = strings.TrimSpace(toString(d["tracking_url"]))
			}
		}
	}
	return update
}

func resolveDeliveryForWebhook(ctx context.Context, fs *cloudfirestore.Client, provider string, update webhookUpdate) (deliveryRecord, string, string) {
	if fs == nil {
		return deliveryRecord{}, "", ""
	}
	if update.ProviderDeliveryID != "" {
		record, storeID, deliveryID := findDeliveryByProviderID(ctx, fs, update.ProviderDeliveryID)
		if storeID != "" {
			if record.Provider == "" {
				record.Provider = provider
			}
			return record, storeID, deliveryID
		}
	}
	if update.OrderID != "" {
		order, _ := fetchOrder(ctx, fs, update.OrderID)
		if order != nil && order.StoreID != "" {
			deliveryID := "del_" + sanitizeID(order.ID)
			return deliveryRecord{
				DeliveryID:         deliveryID,
				OrderID:            order.ID,
				StoreID:            order.StoreID,
				Provider:           provider,
				ProviderDeliveryID: update.ProviderDeliveryID,
				TrackingURL:        update.TrackingURL,
				Status:             normalizeProviderStatus(provider, update.Status),
				CreatedAt:          time.Now().UTC(),
				UpdatedAt:          time.Now().UTC(),
			}, order.StoreID, deliveryID
		}
	}
	return deliveryRecord{}, "", ""
}

func findDeliveryByProviderID(ctx context.Context, fs *cloudfirestore.Client, providerDeliveryID string) (deliveryRecord, string, string) {
	var empty deliveryRecord
	if fs == nil || providerDeliveryID == "" {
		return empty, "", ""
	}
	iter := fs.CollectionGroup(deliveriesCollection).
		Where("providerDeliveryId", "==", providerDeliveryID).
		Limit(1).
		Documents(ctx)
	doc, err := iter.Next()
	if err != nil {
		if err == iterator.Done {
			return empty, "", ""
		}
		return empty, "", ""
	}
	var record deliveryRecord
	if err := doc.DataTo(&record); err != nil {
		return empty, "", ""
	}
	storeID := record.StoreID
	deliveryID := record.DeliveryID
	if doc.Ref != nil && doc.Ref.Parent != nil && doc.Ref.Parent.Parent != nil {
		if storeID == "" {
			storeID = doc.Ref.Parent.Parent.ID
		}
		if deliveryID == "" {
			deliveryID = doc.Ref.ID
		}
	}
	return record, storeID, deliveryID
}

func extractIDFromURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	path := strings.Trim(strings.TrimSpace(u.Path), "/")
	if path == "" {
		return ""
	}
	parts := strings.Split(path, "/")
	return strings.TrimSpace(parts[len(parts)-1])
}

func ensureDeliveryForOrder(
	ctx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	order orderRecord,
) error {
	deliveryID := "del_" + sanitizeID(order.ID)
	snap, err := fs.Collection(storesCollection).Doc(order.StoreID).Collection(deliveriesCollection).Doc(deliveryID).Get(ctx)
	if err == nil && snap.Exists() {
		return nil
	}
	if err != nil && status.Code(err) != codes.NotFound {
		return err
	}

	provider := "mock"
	if order.Delivery != nil && order.Delivery.Quote != nil && strings.TrimSpace(order.Delivery.Quote.Provider) != "" {
		provider = strings.TrimSpace(order.Delivery.Quote.Provider)
	}
	provider = normalizeProvider(provider)
	orderRaw, _ := fetchOrderRaw(ctx, fs, order.ID)
	if orderRaw == nil {
		orderRaw = map[string]any{"id": order.ID, "storeId": order.StoreID}
	}

	providerDeliveryID := ""
	trackingURL := ""
	statusSummary := "dispatched"

	if cfg.ProviderMode == "mock" || provider == "mock" {
		providerDeliveryID = "mock_" + sanitizeID(order.ID)
		trackingURL = "https://tracking.mock/" + url.PathEscape(deliveryID)
	} else {
		storeInfo, err := fetchStoreInfo(ctx, fs, order.StoreID)
		if err != nil {
			return err
		}
		switch provider {
		case "uber_direct":
			id, tracking, pstatus, err := uberCreateDelivery(ctx, httpClient, cfg, storeInfo, orderRaw, order.Delivery)
			if err != nil {
				return err
			}
			providerDeliveryID = id
			trackingURL = tracking
			statusSummary = normalizeProviderStatus(provider, pstatus)
		case "stuart":
			id, tracking, pstatus, err := stuartCreateDelivery(ctx, httpClient, cfg, storeInfo, orderRaw, order.Delivery)
			if err != nil {
				return err
			}
			providerDeliveryID = id
			trackingURL = tracking
			statusSummary = normalizeProviderStatus(provider, pstatus)
		default:
			return fmt.Errorf("unsupported provider: %s", provider)
		}
		if statusSummary == "" {
			statusSummary = "dispatched"
		}
	}

	record := deliveryRecord{
		DeliveryID:         deliveryID,
		OrderID:            order.ID,
		StoreID:            order.StoreID,
		Provider:           provider,
		ProviderDeliveryID: providerDeliveryID,
		TrackingURL:        trackingURL,
		Status:             statusSummary,
		CreatedAt:          time.Now().UTC(),
		UpdatedAt:          time.Now().UTC(),
	}
	if err := upsertDelivery(ctx, fs, order.StoreID, deliveryID, record); err != nil {
		return err
	}

	_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, order.ID, map[string]any{
		"providerDeliveryId":    providerDeliveryID,
		"trackingUrl":           trackingURL,
		"deliveryStatusSummary": statusSummary,
	})

	return publishDeliveryEvent(ctx, pubsubClient, cfg, deliveryEvent{
		Kind:       "delivery_dispatched",
		StoreID:    order.StoreID,
		OrderID:    order.ID,
		DeliveryID: deliveryID,
		Provider:   provider,
		Status:     statusSummary,
		CreatedAt:  time.Now().UTC().Format(time.RFC3339),
		Payload: map[string]any{
			"trackingUrl": trackingURL,
		},
	})
}

func upsertDelivery(ctx context.Context, fs *cloudfirestore.Client, storeID, deliveryID string, record deliveryRecord) error {
	ref := fs.Collection(storesCollection).Doc(storeID).Collection(deliveriesCollection).Doc(deliveryID)
	_, err := ref.Set(ctx, record)
	return err
}

func fetchOrder(ctx context.Context, client *cloudfirestore.Client, orderID string) (*orderRecord, error) {
	snapshot, err := client.Collection(ordersCollection).Doc(orderID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}

	var result orderRecord
	if err := snapshot.DataTo(&result); err != nil {
		return nil, err
	}
	return &result, nil
}

func fetchOrderRaw(ctx context.Context, client *cloudfirestore.Client, orderID string) (map[string]any, error) {
	snapshot, err := client.Collection(ordersCollection).Doc(orderID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	return snapshot.Data(), nil
}

func publishDeliveryEvent(ctx context.Context, client *cloudpubsub.Client, cfg *serviceConfig, evt deliveryEvent) error {
	if client == nil {
		return nil
	}
	topicID := strings.TrimSpace(cfg.DeliveriesEventsTopic)
	if topicID == "" {
		topicID = "deliveries-events"
	}
	topic := client.Topic(topicID)
	payload, err := json.Marshal(evt)
	if err != nil {
		return err
	}
	res := topic.Publish(ctx, &cloudpubsub.Message{Data: payload})
	_, err = res.Get(ctx)
	return err
}

func patchOrderDelivery(ctx context.Context, httpClient *http.Client, tokenSrc oauth2.TokenSource, baseURL, orderID string, fields map[string]any) error {
	if httpClient == nil || tokenSrc == nil {
		return nil
	}
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" || orderID == "" {
		return nil
	}
	b, _ := json.Marshal(fields)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPatch, baseURL+"/orders/"+url.PathEscape(orderID)+"/delivery", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	tok, err := tokenSrc.Token()
	if err == nil && tok != nil && tok.AccessToken != "" {
		req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("order_service_patch_failed status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

func verifyGoogleOidc(r *http.Request, audience string) bool {
	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		return false
	}
	token := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
	if token == "" {
		return false
	}
	payload, err := idtoken.Validate(r.Context(), token, audience)
	if err != nil || payload == nil {
		return false
	}
	return true
}

func splitCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		trimmed := strings.TrimSpace(p)
		if trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func toString(value any) string {
	if value == nil {
		return ""
	}
	s, ok := value.(string)
	if ok {
		return s
	}
	return fmt.Sprintf("%v", value)
}

func stringOrDefault(value any, fallback string) string {
	if value == nil {
		return fallback
	}
	if s, ok := value.(string); ok {
		if strings.TrimSpace(s) == "" {
			return fallback
		}
		return s
	}
	return fallback
}

func sanitizeID(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "unknown"
	}
	value = strings.ReplaceAll(value, ":", "_")
	value = strings.ReplaceAll(value, "/", "_")
	value = strings.ReplaceAll(value, " ", "_")
	return value
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing response: %v", err)
	}
}

var errUnauthorized = errors.New("unauthorized")

func requireAuth(ctx context.Context) error {
	if authUID(ctx) == "" {
		return errUnauthorized
	}
	return nil
}

func fetchRawBody(r *http.Request) ([]byte, error) {
	if r.Body == nil {
		return nil, nil
	}
	b, err := io.ReadAll(r.Body)
	if err != nil {
		return nil, err
	}
	return b, nil
}
