package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
)

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
		r.Use(apiKeyOrBearerJWTMiddleware(cfg))

		r.Get("/stores/{storeID}/menu/snapshot", func(w http.ResponseWriter, r *http.Request) {
			handleVoiceMenuSnapshot(bg, cfg, httpClient, orderTokenSrc, cache, geminiGen, w, r)
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
			handleDeliveryQuote(cfg, httpClient, dispatchTokenSrc, deliveryTokenSrc, w, r)
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
