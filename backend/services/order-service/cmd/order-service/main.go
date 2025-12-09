package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
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

type ctxKey string

const authContextKey ctxKey = "auth_ctx"

const ordersCollection = "orders"

// Valid order status values.
const (
	statusPending   = "pending"
	statusConfirmed = "confirmed"
	statusReady     = "ready"
	statusCompleted = "completed"
	statusCancelled = "cancelled"
)

const menusCollection = "menus"
const menuCacheTTL = 5 * time.Minute

type serviceConfig struct {
	Port           string
	Environment    string
	ProjectID      string
	Credentials    string
	OrdersTopic    string
	MenuUpdatesSub string
	RequireAuth    bool
	OrderTTLDays   int
}

type authContext struct {
	UID      string
	Role     string
	StoreIDs []string
}

type orderItem struct {
	ItemID     string              `json:"itemId" firestore:"itemId"`
	Name       string              `json:"name" firestore:"name"`
	Quantity   int                 `json:"quantity" firestore:"quantity"`
	PriceCents int64               `json:"priceCents" firestore:"priceCents"` // per-unit price in cents
	Modifiers  []modifierSelection `json:"modifiers" firestore:"modifiers"`
	Category   string              `json:"category" firestore:"category"`
}

type modifierSelection struct {
	Name  string `json:"name" firestore:"name"`
	Price int64  `json:"priceCents" firestore:"priceCents"`
}

type orderRequest struct {
	StoreID        string      `json:"storeId"`
	CallSid        string      `json:"callSid"`
	Channel        string      `json:"channel"`
	CustomerName   string      `json:"customerName"`
	Notes          string      `json:"notes"`
	BusinessType   string      `json:"businessType"`
	Items          []orderItem `json:"items"`
	IdempotencyKey string      `json:"idempotencyKey"`
	// Optional overrides; if omitted we compute totals from items.
	SubtotalCents int64 `json:"subtotalCents"`
	TaxCents      int64 `json:"taxCents"`
	FeeCents      int64 `json:"feeCents"`
	DiscountCents int64 `json:"discountCents"`
	TotalCents    int64 `json:"totalCents"`
}

type orderRecord struct {
	ID            string      `json:"id" firestore:"id"`
	StoreID       string      `json:"storeId" firestore:"storeId"`
	CallSid       string      `json:"callSid" firestore:"callSid"`
	Channel       string      `json:"channel" firestore:"channel"`
	CustomerName  string      `json:"customerName" firestore:"customerName"`
	Notes         string      `json:"notes" firestore:"notes"`
	BusinessType  string      `json:"businessType" firestore:"businessType"`
	Items         []orderItem `json:"items" firestore:"items"`
	Status        string      `json:"status" firestore:"status"`
	SubtotalCents int64       `json:"subtotalCents" firestore:"subtotalCents"`
	TaxCents      int64       `json:"taxCents" firestore:"taxCents"`
	FeeCents      int64       `json:"feeCents" firestore:"feeCents"`
	DiscountCents int64       `json:"discountCents" firestore:"discountCents"`
	TotalCents    int64       `json:"totalCents" firestore:"totalCents"`
	CreatedAt     time.Time   `json:"createdAt" firestore:"createdAt"`
	UpdatedAt     time.Time   `json:"updatedAt" firestore:"updatedAt"`
	ExpireAt      time.Time   `json:"expireAt" firestore:"expireAt"`
}

type menuItem struct {
	ID          string     `json:"id" firestore:"id"`
	Name        string     `json:"name" firestore:"name"`
	PriceCents  int64      `json:"priceCents" firestore:"priceCents"`
	Available   bool       `json:"available" firestore:"available"`
	Category    string     `json:"category" firestore:"category"`
	Modifiers   []modifier `json:"modifiers" firestore:"modifiers"`
	Description string     `json:"description" firestore:"description"`
}

type modifier struct {
	Name       string `json:"name" firestore:"name"`
	PriceCents int64  `json:"priceCents" firestore:"priceCents"`
}

type menuRecord struct {
	StoreID   string     `json:"storeId" firestore:"storeId"`
	Items     []menuItem `json:"items" firestore:"items"`
	UpdatedAt time.Time  `json:"updatedAt" firestore:"updatedAt"`
}

type cachedMenu struct {
	menu    *menuRecord
	expires time.Time
}

// Slim payload for agent grounding
type menuSnapshot struct {
	StoreID string     `json:"storeId"`
	Items   []menuItem `json:"items"`
	Updated string     `json:"updated"`
}

func main() {
	_ = godotenv.Load()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed loading config: %v", err)
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

	pubsubClient, err := newPubSubClient(ctx, cfg)
	if err != nil {
		log.Printf("pubsub client not initialised: %v", err)
	}
	defer func() {
		if pubsubClient != nil {
			pubsubClient.Close()
		}
	}()

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
			"service":     "order-service",
			"environment": cfg.Environment,
		})
	})

	router.Get("/metrics", metricsHandler)

	router.Get("/orders/by-call/{callSid}", func(w http.ResponseWriter, r *http.Request) {
		callSid := chi.URLParam(r, "callSid")
		if callSid == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_call_sid"})
			return
		}

		record, err := fetchOrderByCallSid(ctx, firestoreClient, callSid)
		if err != nil {
			log.Printf("failed fetching order by call sid: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if record == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), record.StoreID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		writeJSON(w, http.StatusOK, record)
	})

	router.Post("/orders", func(w http.ResponseWriter, r *http.Request) {
		var payload orderRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.IdempotencyKey == "" {
			payload.IdempotencyKey = r.Header.Get("Idempotency-Key")
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), payload.StoreID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}

		if payload.StoreID == "" || len(payload.Items) == 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		if payload.IdempotencyKey != "" {
			if existing, err := fetchOrderByIdempotencyKey(ctx, firestoreClient, payload.IdempotencyKey); err == nil && existing != nil {
				writeJSON(w, http.StatusOK, existing)
				return
			}
		}

		menuMap, _ := fetchMenuMap(ctx, firestoreClient, payload.StoreID)

		if err := validateItems(payload.Items, menuMap); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}

		if len(menuMap) > 0 {
			payload.Items = applyMenuPricing(payload.Items, menuMap)
		}

		totals := computeTotals(payload)

		now := time.Now().UTC()
		expire := now.Add(time.Duration(cfg.OrderTTLDays) * 24 * time.Hour)

		order := orderRecord{
			ID:            generateOrderID(),
			StoreID:       payload.StoreID,
			CallSid:       payload.CallSid,
			Channel:       payload.Channel,
			CustomerName:  payload.CustomerName,
			Notes:         payload.Notes,
			BusinessType:  payload.BusinessType,
			Items:         payload.Items,
			Status:        statusPending,
			SubtotalCents: totals.SubtotalCents,
			TaxCents:      totals.TaxCents,
			FeeCents:      totals.FeeCents,
			DiscountCents: totals.DiscountCents,
			TotalCents:    totals.TotalCents,
			CreatedAt:     now,
			UpdatedAt:     now,
			ExpireAt:      expire,
		}

		if err := createOrder(ctx, firestoreClient, order, payload.IdempotencyKey); err != nil {
			log.Printf("failed to create order: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_creation_failed"})
			return
		}
		atomic.AddUint64(&ordersCreatedCounter, 1)

		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, order); err != nil {
				log.Printf("failed to publish order event: %v", err)
			}
		}

		log.Printf("created order %s for call %s", order.ID, order.CallSid)
		writeJSON(w, http.StatusAccepted, order)
	})

	router.Get("/orders/{orderID}", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}

		record, err := fetchOrder(ctx, firestoreClient, orderID)
		if err != nil {
			log.Printf("failed fetching order: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if record == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), record.StoreID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		writeJSON(w, http.StatusOK, record)
	})

	// Menu endpoints
	router.Get("/stores/{storeID}/menu", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		menu, err := fetchMenu(ctx, firestoreClient, storeID)
		if err != nil {
			log.Printf("failed fetching menu: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if menu == nil {
			writeJSON(w, http.StatusOK, menuRecord{StoreID: storeID, Items: []menuItem{}, UpdatedAt: time.Now().UTC()})
			return
		}
		writeJSON(w, http.StatusOK, menu)
	})

	// Agent-facing menu snapshot (public, read-only; auth optional depending on env).
	router.Get("/stores/{storeID}/menu/snapshot", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		menu, err := fetchMenuCached(ctx, firestoreClient, storeID)
		if err != nil {
			log.Printf("failed fetching menu snapshot: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if menu == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "menu_not_found"})
			return
		}
		writeJSON(w, http.StatusOK, menuSnapshot{
			StoreID: storeID,
			Items:   menu.Items,
			Updated: menu.UpdatedAt.Format(time.RFC3339),
		})
	})

	router.Put("/stores/{storeID}/menu", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		var payload menuRecord
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if err := validateMenuItems(payload.Items); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		payload.StoreID = storeID
		payload.UpdatedAt = time.Now().UTC()
		if err := upsertMenu(ctx, firestoreClient, payload); err != nil {
			log.Printf("failed to save menu: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "save_failed"})
			return
		}
		invalidateMenuCache(storeID)
		writeJSON(w, http.StatusOK, payload)
	})

	// Menu updates Pub/Sub push (optional). Expects message.data base64 JSON {storeId, updatedAt, jobId, source}
	router.Post("/events/menu-updates", menuUpdatesHandler(ctx, firestoreClient))

	// List orders by store with optional status filter and pagination.
	router.Get("/stores/{storeID}/orders", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}

		statusFilter := r.URL.Query().Get("status")
		limit := parseIntDefault(r.URL.Query().Get("limit"), 50)
		if limit > 200 {
			limit = 200
		}
		orders, err := listOrders(ctx, firestoreClient, storeID, statusFilter, limit)
		if err != nil {
			log.Printf("failed listing orders: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
			return
		}
		writeJSON(w, http.StatusOK, orders)
	})

	// Orders summary per store (counts per status).
	router.Get("/stores/{storeID}/orders/summary", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		summary, err := summarizeOrders(ctx, firestoreClient, storeID, 24*time.Hour)
		if err != nil {
			log.Printf("failed summary: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "summary_failed"})
			return
		}
		writeJSON(w, http.StatusOK, summary)
	})

	// Update order status.
	router.Patch("/orders/{orderID}/status", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		var payload struct {
			Status string `json:"status"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.Status == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		updated, err := updateOrderStatus(ctx, firestoreClient, orderID, payload.Status, r.Context(), cfg.RequireAuth)
		if err != nil {
			if errors.Is(err, errInvalidTransition) {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			if errors.Is(err, errOrderNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
				return
			}
			if errors.Is(err, errUnauthorizedStore) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			log.Printf("failed updating status: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}

		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, *updated); err != nil {
				log.Printf("failed to publish order event: %v", err)
			}
		}

		writeJSON(w, http.StatusOK, updated)
	})

	log.Printf("Order service listening on port %s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, router); err != nil {
		log.Fatalf("server failed: %v", err)
	}
	atomic.AddUint64(&statusUpdateCounter, 1)
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("order-service", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	return &serviceConfig{
		Port:           port,
		Environment:    stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:      stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials:    stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		OrdersTopic:    stringOrDefault(values["PUBSUB_TOPIC_ORDERS"], ""),
		MenuUpdatesSub: stringOrDefault(values["PUBSUB_SUBSCRIPTION_MENU_UPDATES"], ""),
		RequireAuth:    stringOrDefault(values["REQUIRE_AUTH"], "true") == "true",
		OrderTTLDays:   intOrDefault(values["ORDER_TTL_DAYS"], 30),
	}, nil
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
	case string:
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
		return fallback
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

func newPubSubClient(ctx context.Context, cfg *serviceConfig) (*cloudpubsub.Client, error) {
	if cfg.OrdersTopic == "" {
		return nil, nil
	}

	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}

	return cloudpubsub.NewClient(ctx, cfg.ProjectID, opts...)
}

func createOrder(ctx context.Context, client *cloudfirestore.Client, order orderRecord, idempotencyKey string) error {
	return client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		if idempotencyKey != "" {
			// reserve idempotency key
			idDoc := client.Collection(idempotencyCollection).Doc(idempotencyKey)
			// if exists, treat as already processed
			_, err := tx.Get(idDoc)
			if err == nil {
				return nil
			}
			if status.Code(err) != codes.NotFound {
				return err
			}
			if err := tx.Create(idDoc, map[string]interface{}{
				"orderId":   order.ID,
				"storeId":   order.StoreID,
				"createdAt": time.Now().UTC(),
				"expireAt":  time.Now().UTC().Add(48 * time.Hour),
			}); err != nil {
				return err
			}
		}

		doc := client.Collection(ordersCollection).Doc(order.ID)
		if err := tx.Create(doc, order); err != nil {
			return err
		}
		return nil
	})
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

func publishOrderEvent(ctx context.Context, client *cloudpubsub.Client, topicID string, order orderRecord) error {
	topic := client.Topic(topicID)
	payload, err := json.Marshal(order)
	if err != nil {
		return err
	}

	result := topic.Publish(ctx, &cloudpubsub.Message{Data: payload})
	_, err = result.Get(ctx)
	return err
}

func generateOrderID() string {
	return time.Now().UTC().Format("20060102-150405.000000")
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed writing response: %v", err)
	}
}

func logError(message string) error {
	err := errors.New(message)
	log.Print(err)
	return err
}

func fetchOrderByCallSid(ctx context.Context, client *cloudfirestore.Client, callSid string) (*orderRecord, error) {
	iter := client.Collection(ordersCollection).Where("callSid", "==", callSid).Limit(1).Documents(ctx)
	defer iter.Stop()

	doc, err := iter.Next()
	if err != nil {
		if errors.Is(err, iterator.Done) {
			return nil, nil
		}
		return nil, err
	}

	var result orderRecord
	if err := doc.DataTo(&result); err != nil {
		return nil, err
	}
	return &result, nil
}

func fetchOrderByIdempotencyKey(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
	if key == "" {
		return nil, nil
	}
	doc, err := client.Collection(idempotencyCollection).Doc(key).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	orderID, ok := doc.Data()["orderId"].(string)
	if !ok || orderID == "" {
		return nil, nil
	}
	return fetchOrder(ctx, client, orderID)
}

type totals struct {
	SubtotalCents int64
	TaxCents      int64
	FeeCents      int64
	DiscountCents int64
	TotalCents    int64
}

func computeTotals(req orderRequest) totals {
	// If client supplied a non-zero total, trust but normalize; otherwise compute.
	if req.TotalCents > 0 {
		return totals{
			SubtotalCents: req.SubtotalCents,
			TaxCents:      req.TaxCents,
			FeeCents:      req.FeeCents,
			DiscountCents: req.DiscountCents,
			TotalCents:    req.TotalCents,
		}
	}

	var subtotal int64
	for _, item := range req.Items {
		var modifiersSum int64
		for _, mod := range item.Modifiers {
			modifiersSum += mod.Price
		}
		line := (item.PriceCents + modifiersSum) * int64(item.Quantity)
		subtotal += line
	}
	total := subtotal + req.TaxCents + req.FeeCents - req.DiscountCents
	return totals{
		SubtotalCents: subtotal,
		TaxCents:      req.TaxCents,
		FeeCents:      req.FeeCents,
		DiscountCents: req.DiscountCents,
		TotalCents:    total,
	}
}

func validateItems(items []orderItem, menu map[string]menuItem) error {
	if len(items) == 0 {
		return errors.New("items_required")
	}
	for _, item := range items {
		if item.ItemID == "" || item.Name == "" {
			return errors.New("item_missing_fields")
		}
		if item.Quantity <= 0 {
			return errors.New("item_invalid_quantity")
		}
		if item.PriceCents < 0 {
			return errors.New("item_invalid_price")
		}
		if len(menu) > 0 {
			if m, ok := menu[item.ItemID]; ok {
				if !m.Available {
					return fmt.Errorf("item_unavailable:%s", item.ItemID)
				}
				// validate modifier names exist in menu
				if len(item.Modifiers) > 0 && len(m.Modifiers) > 0 {
					modIndex := map[string]modifier{}
					for _, mod := range m.Modifiers {
						modIndex[mod.Name] = mod
					}
					for _, sel := range item.Modifiers {
						if _, ok := modIndex[sel.Name]; !ok {
							return fmt.Errorf("modifier_not_in_menu:%s", sel.Name)
						}
					}
				}
			} else {
				return fmt.Errorf("item_not_in_menu:%s", item.ItemID)
			}
		}
	}
	return nil
}

var errInvalidTransition = errors.New("invalid_status_transition")
var errOrderNotFound = errors.New("order_not_found")
var errUnauthorizedStore = errors.New("unauthorized_store")

func allowedNextStatuses(current string) map[string]bool {
	switch current {
	case statusPending:
		return map[string]bool{statusConfirmed: true, statusCancelled: true}
	case statusConfirmed:
		return map[string]bool{statusReady: true, statusCancelled: true}
	case statusReady:
		return map[string]bool{statusCompleted: true, statusCancelled: true}
	case statusCompleted, statusCancelled:
		return map[string]bool{} // terminal
	default:
		return map[string]bool{}
	}
}

func updateOrderStatus(ctx context.Context, client *cloudfirestore.Client, orderID string, newStatus string, reqCtx context.Context, requireAuth bool) (*orderRecord, error) {
	if newStatus == "" {
		return nil, errInvalidTransition
	}
	docRef := client.Collection(ordersCollection).Doc(orderID)
	err := client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(docRef)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return errOrderNotFound
			}
			return err
		}

		var record orderRecord
		if err := snap.DataTo(&record); err != nil {
			return err
		}

		if requireAuth && !canAccessStore(reqCtx, record.StoreID) {
			return errUnauthorizedStore
		}

		if record.Status == newStatus {
			return nil
		}
		if !allowedNextStatuses(record.Status)[newStatus] {
			return errInvalidTransition
		}

		record.Status = newStatus
		record.UpdatedAt = time.Now().UTC()
		return tx.Set(docRef, record)
	})

	if err != nil {
		return nil, err
	}

	updated, err := fetchOrder(ctx, client, orderID)
	if err != nil {
		return nil, err
	}
	return updated, nil
}

func listOrders(ctx context.Context, client *cloudfirestore.Client, storeID string, statusFilter string, limit int) ([]orderRecord, error) {
	collection := client.Collection(ordersCollection).Where("storeId", "==", storeID)
	if statusFilter != "" {
		collection = collection.Where("status", "==", statusFilter)
	}
	iter := collection.OrderBy("createdAt", cloudfirestore.Desc).Limit(limit).Documents(ctx)
	defer iter.Stop()

	var results []orderRecord
	for {
		snap, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		var record orderRecord
		if err := snap.DataTo(&record); err != nil {
			return nil, err
		}
		results = append(results, record)
	}
	return results, nil
}

func parseIntDefault(value string, fallback int) int {
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
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
			if tokenString == authHeader { // no prefix found
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}
			token, err := client.VerifyIDToken(r.Context(), tokenString)
			if err != nil {
				log.Printf("auth failed: %v", err)
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			var storeIDs []string
			if storesClaim, ok := token.Claims["storeIds"]; ok {
				if s, ok := storesClaim.([]interface{}); ok {
					for _, v := range s {
						if str, ok := v.(string); ok {
							storeIDs = append(storeIDs, str)
						}
					}
				}
			}
			role := ""
			if rClaim, ok := token.Claims["role"].(string); ok {
				role = rClaim
			}
			ctx := context.WithValue(r.Context(), authContextKey, authContext{
				UID:      token.UID,
				Role:     role,
				StoreIDs: storeIDs,
			})
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func fetchMenu(ctx context.Context, client *cloudfirestore.Client, storeID string) (*menuRecord, error) {
	doc, err := client.Collection(menusCollection).Doc(storeID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var menu menuRecord
	if err := doc.DataTo(&menu); err != nil {
		return nil, err
	}
	return &menu, nil
}

// indirection to allow test stubbing.
var fetchMenuFn = fetchMenu

var menuCache sync.Map // storeID -> cachedMenu
var menuCacheHits uint64
var menuCacheMisses uint64

func fetchMenuCached(ctx context.Context, client *cloudfirestore.Client, storeID string) (*menuRecord, error) {
	if v, ok := menuCache.Load(storeID); ok {
		cm := v.(cachedMenu)
		if time.Now().Before(cm.expires) {
			atomic.AddUint64(&menuCacheHits, 1)
			return cm.menu, nil
		}
		menuCache.Delete(storeID)
	}
	atomic.AddUint64(&menuCacheMisses, 1)
	menu, err := fetchMenuFn(ctx, client, storeID)
	if err == nil && menu != nil {
		menuCache.Store(storeID, cachedMenu{menu: menu, expires: time.Now().Add(menuCacheTTL)})
	}
	return menu, err
}

func invalidateMenuCache(storeID string) {
	menuCache.Delete(storeID)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "orders_created_total %d\n", atomic.LoadUint64(&ordersCreatedCounter))
	fmt.Fprintf(w, "order_status_updates_total %d\n", atomic.LoadUint64(&statusUpdateCounter))
	fmt.Fprintf(w, "menu_cache_hits_total %d\n", atomic.LoadUint64(&menuCacheHits))
	fmt.Fprintf(w, "menu_cache_misses_total %d\n", atomic.LoadUint64(&menuCacheMisses))
}

// menuUpdatesHandler processes Pub/Sub push payloads to invalidate/prime menu cache.
func menuUpdatesHandler(ctx context.Context, firestoreClient *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var payload struct {
			Message struct {
				Data string `json:"data"`
			} `json:"message"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.Message.Data == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_data"})
			return
		}
		dataBytes, err := base64.StdEncoding.DecodeString(payload.Message.Data)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_base64"})
			return
		}
		var evt struct {
			StoreID   string    `json:"storeId"`
			UpdatedAt time.Time `json:"updatedAt"`
			JobID     string    `json:"jobId"`
			Source    string    `json:"source"`
		}
		if err := json.Unmarshal(dataBytes, &evt); err != nil || evt.StoreID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_event"})
			return
		}
		log.Printf("menu-update event received store=%s source=%s updatedAt=%s job=%s", evt.StoreID, evt.Source, evt.UpdatedAt, evt.JobID)
		invalidateMenuCache(evt.StoreID)
		// Optionally pre-warm cache
		if _, err := fetchMenuCached(ctx, firestoreClient, evt.StoreID); err != nil {
			log.Printf("menu-update prefetch failed: %v", err)
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func fetchMenuMap(ctx context.Context, client *cloudfirestore.Client, storeID string) (map[string]menuItem, error) {
	menu, err := fetchMenu(ctx, client, storeID)
	if err != nil || menu == nil {
		return map[string]menuItem{}, err
	}
	result := make(map[string]menuItem, len(menu.Items))
	for _, item := range menu.Items {
		result[item.ID] = item
	}
	return result, nil
}

func validateMenuItems(items []menuItem) error {
	for _, item := range items {
		if item.ID == "" || item.Name == "" {
			return errors.New("menu_item_missing_fields")
		}
		if item.PriceCents < 0 {
			return errors.New("menu_item_invalid_price")
		}
		if !item.Available && item.PriceCents == 0 {
			return errors.New("menu_item_invalid_price_for_unavailable")
		}
	}
	return nil
}

func upsertMenu(ctx context.Context, client *cloudfirestore.Client, menu menuRecord) error {
	doc := client.Collection(menusCollection).Doc(menu.StoreID)
	_, err := doc.Set(ctx, menu)
	return err
}

func applyMenuPricing(items []orderItem, menu map[string]menuItem) []orderItem {
	enriched := make([]orderItem, len(items))
	for i, item := range items {
		if m, ok := menu[item.ItemID]; ok {
			price := item.PriceCents
			if price == 0 {
				price = m.PriceCents
			}
			enriched[i] = orderItem{
				ItemID:     item.ItemID,
				Name:       m.Name,
				Category:   m.Category,
				Quantity:   item.Quantity,
				PriceCents: price,
				Modifiers:  item.Modifiers,
			}
		} else {
			enriched[i] = item
		}
	}
	return enriched
}

func canAccessStore(ctx context.Context, storeID string) bool {
	if storeID == "" {
		return false
	}
	val := ctx.Value(authContextKey)
	if val == nil {
		return false
	}
	ac, ok := val.(authContext)
	if !ok {
		return false
	}
	// If no storeIds claim is present, treat as full access (e.g., admin/system).
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

type orderSummary struct {
	Total         int            `json:"total"`
	StatusCounts  map[string]int `json:"statusCounts"`
	Last24hCounts map[string]int `json:"last24hCounts"`
}

func summarizeOrders(ctx context.Context, client *cloudfirestore.Client, storeID string, window time.Duration) (*orderSummary, error) {
	now := time.Now().UTC()
	start := now.Add(-window)

	iter := client.Collection(ordersCollection).
		Where("storeId", "==", storeID).
		OrderBy("createdAt", cloudfirestore.Desc).
		Limit(1000).
		Documents(ctx)
	defer iter.Stop()

	statusCounts := map[string]int{}
	last24Counts := map[string]int{}
	total := 0
	for {
		snap, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		var record orderRecord
		if err := snap.DataTo(&record); err != nil {
			return nil, err
		}
		total++
		statusCounts[record.Status]++
		if record.CreatedAt.After(start) {
			last24Counts[record.Status]++
		}
	}

	return &orderSummary{
		Total:         total,
		StatusCounts:  statusCounts,
		Last24hCounts: last24Counts,
	}, nil
}

const idempotencyCollection = "idempotency_keys"

var (
	ordersCreatedCounter uint64
	statusUpdateCounter  uint64
)
