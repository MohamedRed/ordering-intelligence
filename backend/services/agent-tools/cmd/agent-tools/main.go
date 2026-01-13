package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/golang-jwt/jwt/v4"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
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

type accessTokenClaims struct {
	Scope string `json:"scope"`
	jwt.RegisteredClaims
}

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	bg := context.Background()

	httpClient := &http.Client{
		Timeout: 20 * time.Second,
	}
	orderTokenSrc, err := idtoken.NewTokenSource(context.Background(), cfg.OrderServiceURL)
	if err != nil {
		log.Fatalf("failed to create order-service idtoken source: %v", err)
	}
	var waitTimeTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.WaitTimeServiceURL) != "" {
		waitTimeTokenSrc, err = idtoken.NewTokenSource(context.Background(), cfg.WaitTimeServiceURL)
		if err != nil {
			log.Fatalf("failed to create wait-time-service idtoken source: %v", err)
		}
	}
	var dispatchTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.DispatchServiceURL) != "" {
		dispatchTokenSrc, err = idtoken.NewTokenSource(context.Background(), cfg.DispatchServiceURL)
		if err != nil {
			log.Fatalf("failed to create dispatch-service idtoken source: %v", err)
		}
	}
	var deliveryTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.DeliveryServiceURL) != "" {
		deliveryTokenSrc, err = idtoken.NewTokenSource(context.Background(), cfg.DeliveryServiceURL)
		if err != nil {
			log.Fatalf("failed to create delivery-service idtoken source: %v", err)
		}
	}
	var paymentsTokenSrc oauth2.TokenSource
	if strings.TrimSpace(cfg.PaymentsServiceURL) != "" {
		paymentsTokenSrc, err = idtoken.NewTokenSource(context.Background(), cfg.PaymentsServiceURL)
		if err != nil {
			log.Fatalf("failed to create payments-service idtoken source: %v", err)
		}
	}

	cache, err := newVoiceMenuCache(bg, cfg)
	if err != nil {
		log.Printf("voice menu cache disabled (init failed): %v", err)
		cache = nil
	} else if cache != nil {
		defer func() {
			_ = cache.Close()
		}()
	}

	geminiGen, err := newGeminiGenerator(bg, cfg)
	if err != nil {
		log.Printf("gemini disabled (init failed): %v", err)
		geminiGen = nil
	}

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "agent-tools",
			"environment": cfg.Environment,
		})
	})

	router.Post("/oauth/token", func(w http.ResponseWriter, r *http.Request) {
		handleToken(cfg, w, r)
	})

	router.Route("/v1", func(r chi.Router) {
		// ElevenLabs webhook tools support static request headers (e.g. X-API-Key).
		// We accept either:
		// - Bearer JWT (client_credentials token from /oauth/token), OR
		// - X-API-Key matching our configured secret (dev-friendly).
		r.Use(apiKeyOrBearerJWTMiddleware(cfg))

		// Agent tools (proxy to order-service).
		r.Get("/stores/{storeID}/menu/snapshot", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !requireScopes(r.Context(), w, "menu:read") {
				return
			}
			// Fetch the raw menu snapshot from order-service, then return a voice-friendly response.
			path := "/stores/" + url.PathEscape(storeID) + "/menu/snapshot"
			status, contentType, body, err := fetchFromOrderService(cfg, httpClient, orderTokenSrc, r, http.MethodGet, path, nil)
			if err != nil {
				log.Printf("order-service menu snapshot fetch error: %v", err)
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
				return
			}
			if status < 200 || status >= 300 {
				// Preserve upstream status for non-2xx responses.
				if contentType != "" {
					w.Header().Set("Content-Type", contentType)
				}
				w.WriteHeader(status)
				_, _ = w.Write(body)
				return
			}

			var snap orderMenuSnapshot
			if err := json.Unmarshal(body, &snap); err != nil {
				// If the upstream response isn't in the shape we expect, fall back to passing it through.
				log.Printf("menu snapshot parse failed; passing through raw response: %v", err)
				if contentType != "" {
					w.Header().Set("Content-Type", contentType)
				}
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write(body)
				return
			}

			voice := buildVoiceMenuSnapshot(snap)
			voice.MenuVersion = menuVersionForSnapshot(snap)
			voice.PromptVersion = voiceMenuPromptVersion
			if geminiGen != nil {
				voice.Model = geminiGen.Model()
			} else if strings.TrimSpace(cfg.GeminiModel) != "" {
				voice.Model = strings.TrimSpace(cfg.GeminiModel)
			}
			voice.SuggestedFlowFr = defaultSuggestedFlowFr()
			voice.SpokenMenuFr = deterministicSpokenMenuFr(voice)

			cacheKey := voiceMenuCacheKey(storeID, voice.MenuVersion, firstNonEmpty(voice.Model, "none"), voice.PromptVersion)

			// Cache read (best-effort)
			cacheHit := false
			if cache != nil {
				if art, source, err := cache.GetScript(r.Context(), cacheKey); err == nil && art != nil {
					voice.SpokenMenuFr = art.SpokenMenuFr
					voice.SuggestedFlowFr = art.SuggestedFlowFr
					cacheHit = true
					log.Printf("voice_menu cache_hit source=%s store=%s version=%s", source, storeID, voice.MenuVersion)
				}
			}
			if !cacheHit {
				log.Printf("voice_menu cache_miss store=%s version=%s", storeID, voice.MenuVersion)
			}

			// Cache miss -> try Gemini with tight timeout; on failure keep deterministic fallback.
			if geminiGen != nil && (strings.TrimSpace(voice.SpokenMenuFr) == "" || voice.SpokenMenuFr == deterministicSpokenMenuFr(voice)) {
				gctx, cancel := context.WithTimeout(r.Context(), 2500*time.Millisecond)
				start := time.Now()
				art, err := geminiGen.GenerateMenuScript(gctx, snap, voice)
				cancel()
				if err == nil && art != nil {
					voice.SpokenMenuFr = art.SpokenMenuFr
					voice.SuggestedFlowFr = art.SuggestedFlowFr
					log.Printf("voice_menu gemini_ok store=%s version=%s ms=%d", storeID, voice.MenuVersion, time.Since(start).Milliseconds())
					if cache != nil {
						_ = cache.PutScript(bg, cacheKey, map[string]any{
							"store_id":       storeID,
							"menu_version":   voice.MenuVersion,
							"model":          voice.Model,
							"prompt_version": voice.PromptVersion,
						}, *art)
					}
				} else if cache != nil {
					log.Printf("voice_menu gemini_err store=%s version=%s err=%v", storeID, voice.MenuVersion, err)
					// Background fill: don't block the tool call.
					go func() {
						bctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
						defer cancel()
						art, err := geminiGen.GenerateMenuScript(bctx, snap, voice)
						if err != nil || art == nil {
							return
						}
						_ = cache.PutScript(bctx, cacheKey, map[string]any{
							"store_id":       storeID,
							"menu_version":   voice.MenuVersion,
							"model":          voice.Model,
							"prompt_version": voice.PromptVersion,
						}, *art)
					}()
				}
			}

			writeJSON(w, http.StatusOK, voice)
		})

		// Get a store's current ETA estimate (created->ready median/last/default) for the current daypart.
		r.Get("/stores/{storeID}/wait-time/estimate", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !requireScopes(r.Context(), w, "wait_time:read") {
				return
			}
			if strings.TrimSpace(cfg.WaitTimeServiceURL) == "" || waitTimeTokenSrc == nil {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "wait_time_service_not_configured"})
				return
			}
			path := "/v1/stores/" + url.PathEscape(storeID) + "/wait-time/estimate"
			proxyToWaitTimeService(cfg, httpClient, waitTimeTokenSrc, w, r, http.MethodGet, path, nil)
		})

		// Quote delivery (owned-fleet via dispatch-service in v1).
		r.Post("/stores/{storeID}/delivery/quote", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !requireScopes(r.Context(), w, "orders:write") {
				return
			}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
				return
			}
			if strings.TrimSpace(cfg.DeliveryServiceURL) != "" && deliveryTokenSrc != nil {
				path := "/v1/stores/" + url.PathEscape(storeID) + "/delivery/quote"
				proxyToDeliveryService(cfg, httpClient, deliveryTokenSrc, w, r, http.MethodPost, path, body)
				return
			}
			if strings.TrimSpace(cfg.DispatchServiceURL) == "" || dispatchTokenSrc == nil {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "dispatch_service_not_configured"})
				return
			}
			path := "/v1/stores/" + url.PathEscape(storeID) + "/quote"
			proxyToDispatchService(cfg, httpClient, dispatchTokenSrc, w, r, http.MethodPost, path, body)
		})

		// Search the store menu (menu-only grounding). Returns matching items with required group hints.
		r.Get("/stores/{storeID}/menu/search", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !requireScopes(r.Context(), w, "menu:read") {
				return
			}
			query := strings.TrimSpace(firstNonEmpty(r.URL.Query().Get("q"), r.URL.Query().Get("query")))
			if query == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_query"})
				return
			}

			path := "/stores/" + url.PathEscape(storeID) + "/menu/snapshot"
			status, contentType, body, err := fetchFromOrderService(cfg, httpClient, orderTokenSrc, r, http.MethodGet, path, nil)
			if err != nil {
				log.Printf("order-service menu snapshot fetch error: %v", err)
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
				return
			}
			if status < 200 || status >= 300 {
				if contentType != "" {
					w.Header().Set("Content-Type", contentType)
				}
				w.WriteHeader(status)
				_, _ = w.Write(body)
				return
			}

			var snap orderMenuSnapshotFull
			if err := json.Unmarshal(body, &snap); err != nil {
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_invalid_json"})
				return
			}

			results := searchMenuItems(snap, query, 10)
			writeJSON(w, http.StatusOK, map[string]any{
				"storeId":     storeID,
				"menuVersion": menuVersionForUpdated(snap.Updated),
				"query":       query,
				"results":     results,
			})
		})

		// Get item details including modifier groups (for required follow-up questions).
		r.Get("/stores/{storeID}/menu/items/{itemID}", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			itemID := strings.TrimSpace(chi.URLParam(r, "itemID"))
			if storeID == "" || itemID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
				return
			}
			if !requireScopes(r.Context(), w, "menu:read") {
				return
			}
			path := "/stores/" + url.PathEscape(storeID) + "/menu/snapshot"
			status, contentType, body, err := fetchFromOrderService(cfg, httpClient, orderTokenSrc, r, http.MethodGet, path, nil)
			if err != nil {
				log.Printf("order-service menu snapshot fetch error: %v", err)
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
				return
			}
			if status < 200 || status >= 300 {
				if contentType != "" {
					w.Header().Set("Content-Type", contentType)
				}
				w.WriteHeader(status)
				_, _ = w.Write(body)
				return
			}
			var snap orderMenuSnapshotFull
			if err := json.Unmarshal(body, &snap); err != nil {
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_invalid_json"})
				return
			}
			for _, it := range snap.Items {
				if strings.TrimSpace(it.ID) == itemID {
					writeJSON(w, http.StatusOK, map[string]any{
						"storeId":     storeID,
						"menuVersion": menuVersionForUpdated(snap.Updated),
						"item":        it,
					})
					return
				}
			}
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "item_not_found"})
		})

		// Validate an order draft (menu-only + required modifiers + bundles).
		r.Post("/stores/{storeID}/orders/validate-draft", func(w http.ResponseWriter, r *http.Request) {
			storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
			if storeID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
				return
			}
			if !requireScopes(r.Context(), w, "orders:write") {
				return
			}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
				return
			}
			path := "/stores/" + url.PathEscape(storeID) + "/orders/validate-draft"
			proxyToOrderService(cfg, httpClient, orderTokenSrc, w, r, http.MethodPost, path, body)
		})

		r.Get("/orders/{orderID}", func(w http.ResponseWriter, r *http.Request) {
			orderID := strings.TrimSpace(chi.URLParam(r, "orderID"))
			if orderID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
				return
			}
			// Keep scope requirements simple for now: callers that can create/update orders can also read.
			if !requireScopes(r.Context(), w, "orders:write") {
				return
			}
			path := "/orders/" + url.PathEscape(orderID)
			proxyToOrderService(cfg, httpClient, orderTokenSrc, w, r, http.MethodGet, path, nil)
		})

		r.Post("/orders", func(w http.ResponseWriter, r *http.Request) {
			if !requireScopes(r.Context(), w, "orders:write") {
				return
			}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
				return
			}
			if errResp := validateCreateOrderPayload(body); errResp != nil {
				log.Printf("create-order validation failed: %s", errResp.Message)
				writeJSON(w, http.StatusBadRequest, errResp)
				return
			}
			logCreateOrderPayload(body)
			proxyToOrderService(cfg, httpClient, orderTokenSrc, w, r, http.MethodPost, "/orders", body)
		})

		r.Patch("/orders/{orderID}/status", func(w http.ResponseWriter, r *http.Request) {
			orderID := strings.TrimSpace(chi.URLParam(r, "orderID"))
			if orderID == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
				return
			}
			if !requireScopes(r.Context(), w, "orders:write") {
				return
			}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
				return
			}
			path := "/orders/" + url.PathEscape(orderID) + "/status"
			proxyToOrderService(cfg, httpClient, orderTokenSrc, w, r, http.MethodPatch, path, body)
		})

		registerGroupOrderTools(r, cfg, httpClient, orderTokenSrc, paymentsTokenSrc)
	})

	log.Printf("agent-tools listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
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

func handleToken(cfg *serviceConfig, w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeOAuthError(w, http.StatusMethodNotAllowed, "invalid_request", "method not allowed")
		return
	}

	grantType, scope, clientID, clientSecret, err := parseOAuthClientCredentials(r)
	if err != nil {
		writeOAuthError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}
	if grantType != "client_credentials" {
		writeOAuthError(w, http.StatusBadRequest, "unsupported_grant_type", "unsupported grant_type")
		return
	}

	if clientID == "" {
		clientID = cfg.OAuthClientID
	}

	if subtle.ConstantTimeCompare([]byte(clientID), []byte(cfg.OAuthClientID)) != 1 ||
		subtle.ConstantTimeCompare([]byte(clientSecret), []byte(cfg.OAuthClientSecret)) != 1 {
		// OAuth spec expects 401 + WWW-Authenticate for invalid_client
		w.Header().Set("WWW-Authenticate", `Basic realm="agent-tools", charset="UTF-8"`)
		writeOAuthError(w, http.StatusUnauthorized, "invalid_client", "invalid client credentials")
		return
	}

	// Default scope if not requested by client.
	if strings.TrimSpace(scope) == "" {
		scope = "menu:read orders:read orders:write wait_time:read"
	}

	now := time.Now().UTC()
	exp := now.Add(time.Duration(cfg.TokenTTLSeconds) * time.Second)
	claims := accessTokenClaims{
		Scope: scope,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    cfg.JWTIssuer,
			Subject:   clientID,
			Audience:  []string{cfg.JWTAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(cfg.JWTSigningSecret))
	if err != nil {
		writeOAuthError(w, http.StatusInternalServerError, "server_error", "failed to sign token")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": signed,
		"token_type":   "Bearer",
		"expires_in":   cfg.TokenTTLSeconds,
		"scope":        scope,
	})
}

func parseOAuthClientCredentials(r *http.Request) (grantType, scope, clientID, clientSecret string, err error) {
	// OAuth2 token endpoint is typically form-encoded. We support:
	// - Authorization: Basic base64(client_id:client_secret)
	// - client_id/client_secret in the body
	var form url.Values
	ct := strings.ToLower(strings.TrimSpace(strings.Split(r.Header.Get("Content-Type"), ";")[0]))
	switch ct {
	case "", "application/x-www-form-urlencoded":
		if err := r.ParseForm(); err != nil {
			return "", "", "", "", errors.New("invalid form")
		}
		form = r.PostForm
	case "application/json":
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			return "", "", "", "", errors.New("invalid json")
		}
		form = make(url.Values)
		for k, v := range body {
			form.Set(k, fmt.Sprintf("%v", v))
		}
	default:
		return "", "", "", "", errors.New("unsupported content-type")
	}

	grantType = strings.TrimSpace(form.Get("grant_type"))
	scope = strings.TrimSpace(form.Get("scope"))
	clientID = strings.TrimSpace(form.Get("client_id"))
	clientSecret = strings.TrimSpace(form.Get("client_secret"))

	if u, p, ok := basicAuthClientCreds(r.Header.Get("Authorization")); ok {
		if clientID == "" {
			clientID = u
		}
		if clientSecret == "" {
			clientSecret = p
		}
	}

	if grantType == "" {
		return "", "", "", "", errors.New("missing grant_type")
	}
	if clientSecret == "" {
		return "", "", "", "", errors.New("missing client_secret")
	}
	return grantType, scope, clientID, clientSecret, nil
}

func basicAuthClientCreds(authHeader string) (clientID, clientSecret string, ok bool) {
	authHeader = strings.TrimSpace(authHeader)
	if !strings.HasPrefix(authHeader, "Basic ") {
		return "", "", false
	}
	raw := strings.TrimSpace(strings.TrimPrefix(authHeader, "Basic "))
	decoded, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

func apiKeyOrBearerJWTMiddleware(cfg *serviceConfig) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Allow preflight without auth.
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}

			// 1) Dev-friendly API key path (ElevenLabs webhook tools support static headers).
			if apiKey := strings.TrimSpace(r.Header.Get("X-API-Key")); apiKey != "" {
				// Reuse OAuth client secret as the shared API key (kept in Secret Manager).
				if subtle.ConstantTimeCompare([]byte(apiKey), []byte(cfg.OAuthClientSecret)) == 1 {
					claims := accessTokenClaims{
						Scope: "menu:read orders:read orders:write wait_time:read",
						RegisteredClaims: jwt.RegisteredClaims{
							Issuer:   cfg.JWTIssuer,
							Subject:  "api-key",
							Audience: []string{cfg.JWTAudience},
						},
					}
					ctx := context.WithValue(r.Context(), tokenClaimsContextKey, claims)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}

			// 2) Bearer JWT path.
			authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
			if authHeader == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			if tokenString == authHeader {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}

			var claims accessTokenClaims
			parsed, err := jwt.ParseWithClaims(tokenString, &claims, func(t *jwt.Token) (interface{}, error) {
				if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
					return nil, fmt.Errorf("unexpected signing method")
				}
				return []byte(cfg.JWTSigningSecret), nil
			})
			if err != nil || !parsed.Valid {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			if claims.Issuer != cfg.JWTIssuer {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			if !claims.VerifyAudience(cfg.JWTAudience, true) {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}

			ctx := context.WithValue(r.Context(), tokenClaimsContextKey, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

type ctxKey string

const tokenClaimsContextKey ctxKey = "agent_tools_claims"

func requireScopes(ctx context.Context, w http.ResponseWriter, required ...string) bool {
	val := ctx.Value(tokenClaimsContextKey)
	claims, ok := val.(accessTokenClaims)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return false
	}
	have := scopeSet(claims.Scope)
	for _, need := range required {
		if need == "" {
			continue
		}
		if !have[need] {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "insufficient_scope"})
			return false
		}
	}
	return true
}

func scopeSet(scope string) map[string]bool {
	out := make(map[string]bool)
	for _, s := range strings.Fields(scope) {
		out[strings.TrimSpace(s)] = true
	}
	return out
}

type orderCreatePayloadSummary struct {
	StoreID      string `json:"storeId"`
	TenantID     string `json:"tenantId"`
	CallerID     string `json:"callerId"`
	CallSid      string `json:"callSid"`
	CustomerName string `json:"customerName"`
	Items        []struct {
		ItemID   string `json:"itemId"`
		Name     string `json:"name"`
		Quantity int    `json:"quantity"`
	} `json:"items"`
}

func logCreateOrderPayload(body []byte) {
	var payload orderCreatePayloadSummary
	if err := json.Unmarshal(body, &payload); err != nil {
		log.Printf("create-order payload parse failed: %v", err)
		return
	}
	itemIDs := make([]string, 0, len(payload.Items))
	for _, it := range payload.Items {
		id := strings.TrimSpace(it.ItemID)
		if id == "" {
			id = strings.TrimSpace(it.Name)
		}
		if id != "" {
			itemIDs = append(itemIDs, id)
		}
	}
	log.Printf(
		"create-order payload summary store=%s tenant=%s items=%d ids=%v caller_set=%t callSid_set=%t customer_set=%t",
		strings.TrimSpace(payload.StoreID),
		strings.TrimSpace(payload.TenantID),
		len(payload.Items),
		itemIDs,
		strings.TrimSpace(payload.CallerID) != "",
		strings.TrimSpace(payload.CallSid) != "",
		strings.TrimSpace(payload.CustomerName) != "",
	)
	if len(payload.Items) == 0 {
		log.Printf("create-order payload raw=%s", truncateForLog(body, 2000))
	}
}

func truncateForLog(body []byte, max int) string {
	if len(body) <= max {
		return string(body)
	}
	return string(body[:max]) + "...(truncated)"
}

type createOrderError struct {
	Error         string            `json:"error"`
	Message       string            `json:"message"`
	ExpectedShape map[string]any    `json:"expected_shape,omitempty"`
	Hint          string            `json:"hint,omitempty"`
	MissingFields []string          `json:"missing_fields,omitempty"`
	ItemIndex     int               `json:"item_index,omitempty"`
	ItemMissing   []string          `json:"item_missing_fields,omitempty"`
	Details       map[string]string `json:"details,omitempty"`
}

func validateCreateOrderPayload(body []byte) *createOrderError {
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return &createOrderError{
			Error:   "invalid_json",
			Message: "Request body must be valid JSON.",
			Hint:    "Ensure the tool call sends a JSON object with storeId and items.",
		}
	}

	missing := []string{}
	storeID, _ := payload["storeId"].(string)
	if strings.TrimSpace(storeID) == "" {
		missing = append(missing, "storeId")
	}

	itemsRaw, ok := payload["items"]
	if !ok {
		missing = append(missing, "items")
	}
	if len(missing) > 0 {
		return &createOrderError{
			Error:         "missing_fields",
			Message:       "Missing required fields for create-order.",
			MissingFields: missing,
			ExpectedShape: map[string]any{
				"items": []map[string]string{
					{"itemId": "string", "name": "string", "quantity": "number", "priceCents": "number"},
				},
			},
			Hint: "Use normalizedItems returned by validate-draft.",
		}
	}

	items, ok := itemsRaw.([]any)
	if !ok {
		return &createOrderError{
			Error:   "invalid_items",
			Message: "items must be an array.",
			Hint:    "Pass the normalizedItems array from validate-draft.",
		}
	}
	if len(items) == 0 {
		return &createOrderError{
			Error:   "invalid_items",
			Message: "items must contain at least 1 item.",
			Hint:    "Pass the normalizedItems array from validate-draft.",
		}
	}

	for idx, item := range items {
		itemMap, ok := item.(map[string]any)
		if !ok {
			return &createOrderError{
				Error:     "invalid_item",
				Message:   "Each item must be an object.",
				ItemIndex: idx,
				Hint:      "Use normalizedItems from validate-draft.",
			}
		}
		itemMissing := []string{}
		if strings.TrimSpace(asString(itemMap["itemId"])) == "" {
			itemMissing = append(itemMissing, "itemId")
		}
		if strings.TrimSpace(asString(itemMap["name"])) == "" {
			itemMissing = append(itemMissing, "name")
		}
		if _, ok := itemMap["quantity"]; !ok {
			itemMissing = append(itemMissing, "quantity")
		}
		if _, ok := itemMap["priceCents"]; !ok {
			itemMissing = append(itemMissing, "priceCents")
		}
		if len(itemMissing) > 0 {
			return &createOrderError{
				Error:       "invalid_item_fields",
				Message:     "Item missing required fields.",
				ItemIndex:   idx,
				ItemMissing: itemMissing,
				Hint:        "Use normalizedItems from validate-draft.",
			}
		}
	}

	return nil
}

func asString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
	}
}

func proxyToOrderService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.OrderServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	// Preserve idempotency if present.
	if v := r.Header.Get("Idempotency-Key"); v != "" {
		req.Header.Set("Idempotency-Key", v)
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		log.Printf("failed minting idtoken: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("order-service proxy error: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	// Pass-through response. For create-order failures, log the upstream body to debug.
	if path == "/orders" && resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		log.Printf("order-service /orders failed status=%d body=%s", resp.StatusCode, truncateForLog(respBody, 1200))
		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		_, _ = w.Write(respBody)
		return
	}

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func proxyToWaitTimeService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.WaitTimeServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func proxyToDispatchService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.DispatchServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func proxyToDeliveryService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
	method string,
	path string,
	body []byte,
) {
	target := strings.TrimRight(cfg.DeliveryServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "proxy_failed"})
		return
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_auth_failed"})
		return
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	defer resp.Body.Close()

	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func fetchFromOrderService(
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	r *http.Request,
	method string,
	path string,
	body []byte,
) (status int, contentType string, respBody []byte, err error) {
	target := strings.TrimRight(cfg.OrderServiceURL, "/") + path

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	var reqBody io.Reader
	if body != nil {
		reqBody = bytes.NewReader(body)
	}

	req, err := http.NewRequestWithContext(ctx, method, target, reqBody)
	if err != nil {
		return 0, "", nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	// Preserve idempotency if present.
	if v := r.Header.Get("Idempotency-Key"); v != "" {
		req.Header.Set("Idempotency-Key", v)
	}

	tok, err := tokenSrc.Token()
	if err != nil {
		return 0, "", nil, err
	}
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)

	resp, err := client.Do(req)
	if err != nil {
		return 0, "", nil, err
	}
	defer resp.Body.Close()

	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, "", nil, err
	}
	return resp.StatusCode, resp.Header.Get("Content-Type"), b, nil
}

type orderMenuSnapshot struct {
	StoreID string     `json:"storeId"`
	Items   []menuItem `json:"items"`
	Updated string     `json:"updated"`
}

type menuItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	PriceCents  int    `json:"priceCents"`
	Available   bool   `json:"available"`
	Category    string `json:"category"`
	Description string `json:"description"`
}

type voiceMenuSnapshot struct {
	StoreID         string              `json:"storeId"`
	MenuVersion     string              `json:"menuVersion"`
	Updated         string              `json:"updated,omitempty"`
	Locale          string              `json:"locale"`
	Currency        string              `json:"currency"`
	Model           string              `json:"model,omitempty"`
	PromptVersion   string              `json:"promptVersion,omitempty"`
	SummaryFR       string              `json:"summaryFr"`
	SpokenMenuFr    string              `json:"spokenMenuFr"`
	SuggestedFlowFr []string            `json:"suggestedFlowFr"`
	Categories      []voiceMenuCategory `json:"categories"`
}

type voiceMenuCategory struct {
	Name  string          `json:"name"`
	Items []voiceMenuItem `json:"items"`
}

type voiceMenuItem struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Available     bool   `json:"available"`
	Description   string `json:"description,omitempty"`
	PriceCents    int    `json:"priceCents"`
	PriceDisplay  string `json:"priceDisplay"`
	PriceSpeechFR string `json:"priceSpeechFr"`
}

func buildVoiceMenuSnapshot(snap orderMenuSnapshot) voiceMenuSnapshot {
	// Group by category.
	byCat := make(map[string][]voiceMenuItem)
	for _, it := range snap.Items {
		cat := strings.TrimSpace(it.Category)
		if cat == "" {
			cat = "Menu"
		}
		v := voiceMenuItem{
			ID:            strings.TrimSpace(it.ID),
			Name:          strings.TrimSpace(it.Name),
			Available:     it.Available,
			Description:   strings.TrimSpace(it.Description),
			PriceCents:    it.PriceCents,
			PriceDisplay:  formatEURFr(it.PriceCents),
			PriceSpeechFR: speakEURFr(it.PriceCents),
		}
		if v.Description == "" {
			v.Description = ""
		}
		byCat[cat] = append(byCat[cat], v)
	}

	// Stable ordering: categories alpha; items alpha within category.
	cats := make([]string, 0, len(byCat))
	for k := range byCat {
		cats = append(cats, k)
	}
	sort.Strings(cats)
	outCats := make([]voiceMenuCategory, 0, len(cats))
	totalItems := 0
	for _, c := range cats {
		items := byCat[c]
		sort.Slice(items, func(i, j int) bool {
			return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
		})
		// Drop empty descriptions from JSON output by setting to empty and relying on omitempty.
		for i := range items {
			if strings.TrimSpace(items[i].Description) == "" {
				items[i].Description = ""
			}
		}
		outCats = append(outCats, voiceMenuCategory{Name: c, Items: items})
		totalItems += len(items)
	}

	summary := fmt.Sprintf("Menu chargé: %d article(s), %d catégorie(s). Pour annoncer le menu, présente d'abord les catégories, puis propose 3 à 5 options populaires et demande les préférences du client.", totalItems, len(outCats))

	return voiceMenuSnapshot{
		StoreID:    snap.StoreID,
		Updated:    snap.Updated,
		Locale:     "fr-FR",
		Currency:   "EUR",
		SummaryFR:  summary,
		Categories: outCats,
	}
}

func formatEURFr(priceCents int) string {
	if priceCents <= 0 {
		return "Gratuit"
	}
	euros := priceCents / 100
	cents := priceCents % 100
	return fmt.Sprintf("%s,%02d €", formatIntWithSpaces(euros), cents)
}

func formatIntWithSpaces(n int) string {
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	var b strings.Builder
	pre := len(s) % 3
	if pre == 0 {
		pre = 3
	}
	b.WriteString(s[:pre])
	for i := pre; i < len(s); i += 3 {
		b.WriteString(" ")
		b.WriteString(s[i : i+3])
	}
	return b.String()
}

func speakEURFr(priceCents int) string {
	if priceCents <= 0 {
		return "gratuit"
	}
	euros := priceCents / 100
	cents := priceCents % 100

	// Euros part.
	euroWord := "euros"
	if euros == 1 {
		euroWord = "euro"
	}
	if cents == 0 {
		return fmt.Sprintf("%s %s", frenchWords(euros), euroWord)
	}

	// Cents part.
	centWord := "centimes"
	if cents == 1 {
		centWord = "centime"
	}

	// Natural French: "huit euros cinquante" (omit "centimes") when cents is >=10 and not a single-digit.
	if cents >= 10 && cents%10 == 0 {
		return fmt.Sprintf("%s %s %s", frenchWords(euros), euroWord, frenchWords(cents))
	}
	if cents >= 10 {
		return fmt.Sprintf("%s %s %s", frenchWords(euros), euroWord, frenchWords(cents))
	}
	// For single-digit cents, say "et cinq centimes" to avoid "zéro cinq".
	return fmt.Sprintf("%s %s et %s %s", frenchWords(euros), euroWord, frenchWords(cents), centWord)
}

func frenchWords(n int) string {
	if n < 0 {
		return "moins " + frenchWords(-n)
	}
	if n == 0 {
		return "zéro"
	}
	if n < 100 {
		return frenchWordsUnder100(n)
	}
	if n < 1000 {
		h := n / 100
		r := n % 100
		if h == 1 {
			if r == 0 {
				return "cent"
			}
			return "cent " + frenchWordsUnder100(r)
		}
		// plural 'cents' only when no remainder
		if r == 0 {
			return frenchWordsUnder100(h) + " cents"
		}
		return frenchWordsUnder100(h) + " cent " + frenchWordsUnder100(r)
	}
	if n < 1_000_000 {
		th := n / 1000
		r := n % 1000
		var left string
		if th == 1 {
			left = "mille"
		} else {
			left = frenchWords(th) + " mille"
		}
		if r == 0 {
			return left
		}
		return left + " " + frenchWords(r)
	}
	if n < 1_000_000_000 {
		m := n / 1_000_000
		r := n % 1_000_000
		mw := "millions"
		if m == 1 {
			mw = "million"
		}
		left := frenchWords(m) + " " + mw
		if r == 0 {
			return left
		}
		return left + " " + frenchWords(r)
	}
	// Good enough for menu prices.
	return fmt.Sprintf("%d", n)
}

func frenchWordsUnder100(n int) string {
	units := map[int]string{
		0:  "zéro",
		1:  "un",
		2:  "deux",
		3:  "trois",
		4:  "quatre",
		5:  "cinq",
		6:  "six",
		7:  "sept",
		8:  "huit",
		9:  "neuf",
		10: "dix",
		11: "onze",
		12: "douze",
		13: "treize",
		14: "quatorze",
		15: "quinze",
		16: "seize",
	}
	if n <= 16 {
		return units[n]
	}
	if n < 20 {
		switch n {
		case 17:
			return "dix-sept"
		case 18:
			return "dix-huit"
		case 19:
			return "dix-neuf"
		}
	}
	tens := map[int]string{
		20: "vingt",
		30: "trente",
		40: "quarante",
		50: "cinquante",
		60: "soixante",
		80: "quatre-vingt",
	}
	if n < 70 {
		t := (n / 10) * 10
		u := n % 10
		if u == 0 {
			return tens[t]
		}
		if u == 1 {
			return tens[t] + " et un"
		}
		return tens[t] + "-" + units[u]
	}
	if n < 80 {
		// 70..79 = 60 + 10..19
		if n == 71 {
			return "soixante et onze"
		}
		return "soixante-" + frenchWordsUnder100(n-60)
	}
	// 80..99 = 80 + 0..19
	r := n - 80
	if r == 0 {
		return "quatre-vingts"
	}
	if r == 1 {
		return "quatre-vingt-un"
	}
	if r <= 16 {
		return "quatre-vingt-" + units[r]
	}
	if r < 20 {
		return "quatre-vingt-" + frenchWordsUnder100(r)
	}
	// 90..99 = 80 + 10..19
	return "quatre-vingt-" + frenchWordsUnder100(r)
}

func writeOAuthError(w http.ResponseWriter, status int, code, desc string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"error":             code,
		"error_description": desc,
	})
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func stringOrDefault(value interface{}, fallback string) string {
	if value == nil {
		return fallback
	}
	switch v := value.(type) {
	case string:
		if v == "" {
			return fallback
		}
		return v
	case int64:
		return fmt.Sprintf("%d", v)
	case float64:
		return fmt.Sprintf("%f", v)
	default:
		return fallback
	}
}

func intOrDefault(value interface{}, fallback int) int {
	if value == nil {
		return fallback
	}
	switch v := value.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	default:
		return fallback
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

func intFromEnv(name string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	// Allow simple ints only.
	var n int
	_, err := fmt.Sscanf(raw, "%d", &n)
	if err != nil {
		return fallback
	}
	return n
}
