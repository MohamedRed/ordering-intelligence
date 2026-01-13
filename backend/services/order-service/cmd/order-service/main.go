package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"sort"
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
	"github.com/go-chi/cors"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type ctxKey string

const authContextKey ctxKey = "auth_ctx"

const ordersCollection = "orders"
const storesCollection = "stores"
const tenantsCollection = "tenants"
const orderCountersCollection = "order_counters"
const waitTimeStatsSubcollection = "wait_time_stats"
const waitTimeDailySubcollection = "wait_time_daily"

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
	Port                  string
	Environment           string
	ProjectID             string
	Credentials           string
	OrdersTopic           string
	MenuUpdatesSub        string
	RequireAuth           bool
	OrderTTLDays          int
	APIKey                string
	InternalAuthAudience  string
	InternalAllowedEmails []string
	WaitTimeMinSamples    int
	PaymentsServiceURL    string
}

type authContext struct {
	UID      string
	Role     string
	StoreIDs []string
}

type storeDoc struct {
	TenantID   string         `firestore:"tenant_id"`
	TenantID2  string         `firestore:"tenantId"`
	OrderComms map[string]any `firestore:"order_comms"`
}

type tenantDoc struct {
	Timezone string `firestore:"timezone"`
}

type waitTimeStatsDoc struct {
	Count               int       `firestore:"count"`
	Samples             []int     `firestore:"samples"`
	LastDurationMinutes int       `firestore:"lastDurationMinutes"`
	MedianMinutes       int       `firestore:"medianMinutes"`
	P90Minutes          int       `firestore:"p90Minutes"`
	UpdatedAt           time.Time `firestore:"updatedAt"`
	DaypartKey          string    `firestore:"daypartKey"`
}

type waitTimeAgg struct {
	Count               int `json:"count"`
	MedianMinutes       int `json:"medianMinutes"`
	P90Minutes          int `json:"p90Minutes"`
	LastDurationMinutes int `json:"lastDurationMinutes"`
}

type waitTimeDailyPoint struct {
	Date      string                 `json:"date"`
	UpdatedAt string                 `json:"updatedAt,omitempty"`
	Overall   waitTimeAgg            `json:"overall"`
	Dayparts  map[string]waitTimeAgg `json:"dayparts,omitempty"`
}

type storeWaitTimeMeta struct {
	tenantID           string
	defaultWaitMinutes int
	loc                *time.Location
	fetchedAt          time.Time
}

type storeWaitTimeMetaCache struct {
	mu   sync.Mutex
	byID map[string]storeWaitTimeMeta
}

func newStoreWaitTimeMetaCache() *storeWaitTimeMetaCache {
	return &storeWaitTimeMetaCache{byID: make(map[string]storeWaitTimeMeta)}
}

func (c *storeWaitTimeMetaCache) get(storeID string) (storeWaitTimeMeta, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	m, ok := c.byID[storeID]
	if !ok {
		return storeWaitTimeMeta{}, false
	}
	if time.Since(m.fetchedAt) > 5*time.Minute {
		return storeWaitTimeMeta{}, false
	}
	return m, true
}

func (c *storeWaitTimeMetaCache) set(storeID string, m storeWaitTimeMeta) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.byID[storeID] = m
}

type orderItem struct {
	ItemID           string              `json:"itemId" firestore:"itemId"`
	Name             string              `json:"name" firestore:"name"`
	Quantity         int                 `json:"quantity" firestore:"quantity"`
	PriceCents       int64               `json:"priceCents" firestore:"priceCents"` // per-unit price in cents
	ParticipantID    string              `json:"participantId,omitempty" firestore:"participantId,omitempty"`
	ParticipantLabel string              `json:"participantLabel,omitempty" firestore:"participantLabel,omitempty"`
	Modifiers        []modifierSelection `json:"modifiers" firestore:"modifiers"`
	// Structured modifier selections (preferred). If present, these are used instead of legacy Modifiers.
	ModifierSelections []modifierSelectionV2 `json:"modifierSelections,omitempty" firestore:"modifierSelections,omitempty"`
	Category           string                `json:"category" firestore:"category"`
	// Bundles/combo-builder grouping (optional).
	BundleID   string `json:"bundleId,omitempty" firestore:"bundleId,omitempty"`
	BundleRole string `json:"bundleRole,omitempty" firestore:"bundleRole,omitempty"` // e.g. main|drink|side|extra
}

type modifierSelection struct {
	Name  string `json:"name" firestore:"name"`
	Price int64  `json:"priceCents" firestore:"priceCents"`
}

type modifierSelectionV2 struct {
	GroupID    string `json:"groupId" firestore:"groupId"`
	OptionID   string `json:"optionId" firestore:"optionId"`
	Name       string `json:"name" firestore:"name"`
	PriceCents int64  `json:"priceCents" firestore:"priceCents"`
}

type orderRequest struct {
	StoreID        string            `json:"storeId"`
	CallSid        string            `json:"callSid"`
	Channel        string            `json:"channel"`
	CustomerName   string            `json:"customerName"`
	TenantID       string            `json:"tenantId"`
	CustomerID     string            `json:"customerId,omitempty"`
	CallerID       string            `json:"callerId"`
	ChannelContact *channelContact   `json:"channelContact,omitempty"`
	Origin         *orderOrigin      `json:"origin,omitempty"`
	Notes          string            `json:"notes"`
	BusinessType   string            `json:"businessType"`
	Items          []orderItem       `json:"items"`
	IdempotencyKey string            `json:"idempotencyKey"`
	PaymentMethod  string            `json:"paymentMethod,omitempty"`
	Fuel           *fuelOrderRequest `json:"fuel,omitempty"`
	// Fulfillment: pickup (default) or delivery.
	FulfillmentType string         `json:"fulfillmentType"`
	Delivery        *orderDelivery `json:"delivery,omitempty"`
	// Optional overrides; if omitted we compute totals from items.
	SubtotalCents int64 `json:"subtotalCents"`
	TaxCents      int64 `json:"taxCents"`
	FeeCents      int64 `json:"feeCents"`
	DiscountCents int64 `json:"discountCents"`
	TotalCents    int64 `json:"totalCents"`
}

type channelContact struct {
	Channel     string         `json:"channel" firestore:"channel"`
	AccountID   string         `json:"accountId,omitempty" firestore:"accountId,omitempty"`
	UserID      string         `json:"userId,omitempty" firestore:"userId,omitempty"`
	ThreadID    string         `json:"threadId,omitempty" firestore:"threadId,omitempty"`
	DisplayName string         `json:"displayName,omitempty" firestore:"displayName,omitempty"`
	Locale      string         `json:"locale,omitempty" firestore:"locale,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty" firestore:"metadata,omitempty"`
}

// Valid notifyMode values for status change comms orchestration.
const (
	notifyModeAuto = "auto"
	notifyModeSMS  = "sms"
	notifyModeCall = "call"
	notifyModeNone = "none"
)

type orderStatusChange struct {
	PreviousStatus string    `json:"previousStatus" firestore:"previousStatus"`
	NewStatus      string    `json:"newStatus" firestore:"newStatus"`
	ChangedAt      time.Time `json:"changedAt" firestore:"changedAt"`
	ChangedBy      string    `json:"changedBy,omitempty" firestore:"changedBy,omitempty"`
	NotifyMode     string    `json:"notifyMode,omitempty" firestore:"notifyMode,omitempty"`
	Note           string    `json:"note,omitempty" firestore:"note,omitempty"`
	TemplateID     string    `json:"templateId,omitempty" firestore:"templateId,omitempty"`
}

type customerCommsPayload struct {
	Kind       string `json:"kind" firestore:"kind"`
	NotifyMode string `json:"notifyMode,omitempty" firestore:"notifyMode,omitempty"`
	Note       string `json:"note,omitempty" firestore:"note,omitempty"`
	TemplateID string `json:"templateId,omitempty" firestore:"templateId,omitempty"`
}

type orderCustomerCommsEvent struct {
	Kind      string               `json:"kind"`
	Order     orderRecord          `json:"order"`
	Comms     customerCommsPayload `json:"comms"`
	CreatedAt time.Time            `json:"createdAt"`
}

type orderRecord struct {
	ID              string             `json:"id" firestore:"id"`
	DisplayNumber   string             `json:"displayNumber,omitempty" firestore:"displayNumber,omitempty"`
	StoreID         string             `json:"storeId" firestore:"storeId"`
	CallSid         string             `json:"callSid" firestore:"callSid"`
	Channel         string             `json:"channel" firestore:"channel"`
	CustomerName    string             `json:"customerName" firestore:"customerName"`
	TenantID        string             `json:"tenantId" firestore:"tenantId"`
	CustomerID      string             `json:"customerId,omitempty" firestore:"customerId,omitempty"`
	CallerID        string             `json:"callerId" firestore:"callerId"`
	ChannelContact  *channelContact    `json:"channelContact,omitempty" firestore:"channelContact,omitempty"`
	Origin          *orderOrigin       `json:"origin,omitempty" firestore:"origin,omitempty"`
	Notes           string             `json:"notes" firestore:"notes"`
	BusinessType    string             `json:"businessType" firestore:"businessType"`
	PaymentMethod   string             `json:"paymentMethod,omitempty" firestore:"paymentMethod,omitempty"`
	Items           []orderItem        `json:"items" firestore:"items"`
	Fuel            *fuelOrder         `json:"fuel,omitempty" firestore:"fuel,omitempty"`
	Status          string             `json:"status" firestore:"status"`
	FulfillmentType string             `json:"fulfillmentType" firestore:"fulfillmentType"`
	Delivery        *orderDelivery     `json:"delivery,omitempty" firestore:"delivery,omitempty"`
	StatusChange    *orderStatusChange `json:"statusChange,omitempty" firestore:"statusChange,omitempty"`
	ConfirmedAt     *time.Time         `json:"confirmedAt,omitempty" firestore:"confirmedAt,omitempty"`
	ReadyAt         *time.Time         `json:"readyAt,omitempty" firestore:"readyAt,omitempty"`
	CompletedAt     *time.Time         `json:"completedAt,omitempty" firestore:"completedAt,omitempty"`
	CancelledAt     *time.Time         `json:"cancelledAt,omitempty" firestore:"cancelledAt,omitempty"`
	SubtotalCents   int64              `json:"subtotalCents" firestore:"subtotalCents"`
	TaxCents        int64              `json:"taxCents" firestore:"taxCents"`
	FeeCents        int64              `json:"feeCents" firestore:"feeCents"`
	DiscountCents   int64              `json:"discountCents" firestore:"discountCents"`
	TotalCents      int64              `json:"totalCents" firestore:"totalCents"`
	CreatedAt       time.Time          `json:"createdAt" firestore:"createdAt"`
	UpdatedAt       time.Time          `json:"updatedAt" firestore:"updatedAt"`
	ExpireAt        time.Time          `json:"expireAt" firestore:"expireAt"`
}

type deliveryLatLng struct {
	Lat float64 `json:"lat" firestore:"lat"`
	Lng float64 `json:"lng" firestore:"lng"`
}

type deliveryAddress struct {
	Line1      string `json:"line1,omitempty" firestore:"line1,omitempty"`
	Line2      string `json:"line2,omitempty" firestore:"line2,omitempty"`
	City       string `json:"city,omitempty" firestore:"city,omitempty"`
	State      string `json:"state,omitempty" firestore:"state,omitempty"`
	PostalCode string `json:"postalCode,omitempty" firestore:"postalCode,omitempty"`
	Country    string `json:"country,omitempty" firestore:"country,omitempty"`
	Formatted  string `json:"formatted,omitempty" firestore:"formatted,omitempty"`
}

type deliveryQuote struct {
	Provider          string     `json:"provider,omitempty" firestore:"provider,omitempty"`
	ProviderFeeCents  int64      `json:"providerFeeCents,omitempty" firestore:"providerFeeCents,omitempty"`
	DropoffEtaMinutes int        `json:"dropoffEtaMinutes,omitempty" firestore:"dropoffEtaMinutes,omitempty"`
	QuoteExpiresAt    *time.Time `json:"quoteExpiresAt,omitempty" firestore:"quoteExpiresAt,omitempty"`
	Currency          string     `json:"currency,omitempty" firestore:"currency,omitempty"`
}

type orderDelivery struct {
	FleetMode string `json:"fleetMode,omitempty" firestore:"fleetMode,omitempty"` // third_party|owned_fleet

	DropoffAddress *deliveryAddress `json:"dropoffAddress,omitempty" firestore:"dropoffAddress,omitempty"`
	DropoffLatLng  *deliveryLatLng  `json:"dropoffLatLng,omitempty" firestore:"dropoffLatLng,omitempty"`
	Instructions   string           `json:"instructions,omitempty" firestore:"instructions,omitempty"`

	Quote *deliveryQuote `json:"quote,omitempty" firestore:"quote,omitempty"`

	CustomerPaysDeliveryFee           bool  `json:"customerPaysDeliveryFee,omitempty" firestore:"customerPaysDeliveryFee,omitempty"`
	DeliveryFeeCentsChargedToCustomer int64 `json:"deliveryFeeCentsChargedToCustomer,omitempty" firestore:"deliveryFeeCentsChargedToCustomer,omitempty"`

	ProviderDeliveryID string `json:"providerDeliveryId,omitempty" firestore:"providerDeliveryId,omitempty"`
	TrackingURL        string `json:"trackingUrl,omitempty" firestore:"trackingUrl,omitempty"`

	AssignedDriverID      string `json:"assignedDriverId,omitempty" firestore:"assignedDriverId,omitempty"`
	AssignedRouteID       string `json:"assignedRouteId,omitempty" firestore:"assignedRouteId,omitempty"`
	AssignmentStatus      string `json:"assignmentStatus,omitempty" firestore:"assignmentStatus,omitempty"` // pending|assigned|declined|expired|reassigned
	DeliveryStatusSummary string `json:"deliveryStatusSummary,omitempty" firestore:"deliveryStatusSummary,omitempty"`
}

type deliveryQuotePatch struct {
	Provider          *string `json:"provider,omitempty"`
	ProviderFeeCents  *int64  `json:"providerFeeCents,omitempty"`
	DropoffEtaMinutes *int    `json:"dropoffEtaMinutes,omitempty"`
	QuoteExpiresAt    *string `json:"quoteExpiresAt,omitempty"` // RFC3339
	Currency          *string `json:"currency,omitempty"`
}

type orderDeliveryPatch struct {
	AssignedDriverID      *string             `json:"assignedDriverId,omitempty"`
	AssignedRouteID       *string             `json:"assignedRouteId,omitempty"`
	AssignmentStatus      *string             `json:"assignmentStatus,omitempty"`
	ProviderDeliveryID    *string             `json:"providerDeliveryId,omitempty"`
	TrackingURL           *string             `json:"trackingUrl,omitempty"`
	DeliveryStatusSummary *string             `json:"deliveryStatusSummary,omitempty"`
	Quote                 *deliveryQuotePatch `json:"quote,omitempty"`
}

type menuItem struct {
	ID             string          `json:"id" firestore:"id"`
	Name           string          `json:"name" firestore:"name"`
	PriceCents     int64           `json:"priceCents" firestore:"priceCents"`
	Available      bool            `json:"available" firestore:"available"`
	Category       string          `json:"category" firestore:"category"`
	Modifiers      []modifier      `json:"modifiers" firestore:"modifiers"`
	ModifierGroups []modifierGroup `json:"modifierGroups,omitempty" firestore:"modifierGroups,omitempty"`
	Description    string          `json:"description" firestore:"description"`
}

type modifier struct {
	Name       string `json:"name" firestore:"name"`
	PriceCents int64  `json:"priceCents" firestore:"priceCents"`
}

type modifierGroup struct {
	ID            string           `json:"id" firestore:"id"`
	Name          string           `json:"name" firestore:"name"`
	Required      bool             `json:"required" firestore:"required"`
	MinSelections int              `json:"minSelections" firestore:"minSelections"`
	MaxSelections int              `json:"maxSelections" firestore:"maxSelections"`
	Options       []modifierOption `json:"options" firestore:"options"`
}

type modifierOption struct {
	ID         string `json:"id" firestore:"id"`
	Name       string `json:"name" firestore:"name"`
	PriceCents int64  `json:"priceCents" firestore:"priceCents"`
}

type menuRecord struct {
	StoreID     string       `json:"storeId" firestore:"storeId"`
	Items       []menuItem   `json:"items" firestore:"items"`
	BundleRules []bundleRule `json:"bundleRules,omitempty" firestore:"bundleRules,omitempty"`
	UpdatedAt   time.Time    `json:"updatedAt" firestore:"updatedAt"`
}

type bundleRule struct {
	BundleID        string            `json:"bundleId" firestore:"bundleId"`
	DisplayName     string            `json:"displayName" firestore:"displayName"`
	TriggerItemID   string            `json:"triggerItemId,omitempty" firestore:"triggerItemId,omitempty"`
	TriggerCategory string            `json:"triggerCategory,omitempty" firestore:"triggerCategory,omitempty"`
	Components      []bundleComponent `json:"components" firestore:"components"`
	PromptHintsFr   string            `json:"promptHintsFr,omitempty" firestore:"promptHintsFr,omitempty"`
}

type bundleComponent struct {
	Role             string   `json:"role" firestore:"role"` // drink|side|...
	AllowedItemIDs   []string `json:"itemIds,omitempty" firestore:"itemIds,omitempty"`
	AllowedCategory  string   `json:"category,omitempty" firestore:"category,omitempty"`
	RequiredGroupIDs []string `json:"requiredGroupIds,omitempty" firestore:"requiredGroupIds,omitempty"`
}

type cachedMenu struct {
	menu    *menuRecord
	expires time.Time
}

// Slim payload for agent grounding
type menuSnapshot struct {
	StoreID     string       `json:"storeId"`
	Items       []menuItem   `json:"items"`
	BundleRules []bundleRule `json:"bundleRules,omitempty"`
	Updated     string       `json:"updated"`
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

	waitTimeMetaCache := newStoreWaitTimeMetaCache()

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)
	router.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins(),
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Requested-With"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Auth: accept X-API-Key if provided; otherwise accept internal Google ID tokens (IAM-style);
	// otherwise fall back to Firebase ID token when required.
	router.Use(apiKeyOrFirebaseMiddleware(cfg.APIKey, authClient, cfg.RequireAuth, cfg.InternalAuthAudience, cfg.InternalAllowedEmails))

	registerGroupOrderRoutes(router, firestoreClient, pubsubClient, cfg)
	registerOrderChannelContactRoutes(router, firestoreClient, pubsubClient, cfg)

	registerHealthRoutes(router, cfg)

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
		payload.PaymentMethod = strings.TrimSpace(payload.PaymentMethod)

		fulfillmentType := strings.ToLower(strings.TrimSpace(payload.FulfillmentType))
		if fulfillmentType == "" {
			fulfillmentType = "pickup"
		}
		if fulfillmentType != "pickup" && fulfillmentType != "delivery" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_fulfillment_type"})
			return
		}
		if fulfillmentType == "delivery" {
			if payload.Delivery == nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_delivery"})
				return
			}
			payload.Delivery.FleetMode = strings.ToLower(strings.TrimSpace(payload.Delivery.FleetMode))
			if payload.Delivery.FleetMode != "owned_fleet" && payload.Delivery.FleetMode != "third_party" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_delivery_fleet_mode"})
				return
			}
			hasLatLng := payload.Delivery.DropoffLatLng != nil && payload.Delivery.DropoffLatLng.Lat != 0 && payload.Delivery.DropoffLatLng.Lng != 0
			hasAddress := false
			if payload.Delivery.DropoffAddress != nil {
				a := payload.Delivery.DropoffAddress
				hasAddress = strings.TrimSpace(a.Formatted) != "" ||
					strings.TrimSpace(a.Line1) != "" ||
					strings.TrimSpace(a.City) != ""
			}
			if !hasLatLng && !hasAddress {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_dropoff"})
				return
			}
		}

		if payload.IdempotencyKey != "" {
			if existing, err := fetchOrderByIdempotencyKey(ctx, firestoreClient, payload.IdempotencyKey); err == nil && existing != nil {
				writeJSON(w, http.StatusOK, existing)
				return
			}
		}

		isGasOrder := isGasStationBusinessType(payload.BusinessType)
		menu, err := fetchMenuCached(ctx, firestoreClient, payload.StoreID)
		if err != nil {
			log.Printf("failed fetching menu for order validation: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if menu == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "menu_not_found"})
			return
		}

		var fuelRecord *fuelOrder
		var totals totals
		if isGasOrder {
			if strings.TrimSpace(payload.PaymentMethod) == "" {
				payload.PaymentMethod = "card"
			}
			if strings.ToLower(strings.TrimSpace(payload.PaymentMethod)) != "card" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "gas_card_only"})
				return
			}
			if payload.Fuel == nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fuel"})
				return
			}
			fuel, fuelTotals, err := normalizeFuelOrder(*menu, *payload.Fuel)
			if err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
			fuelRecord = &fuel
			payload.Items = []orderItem{}
			totals = fuelTotals
		} else {
			normalizedItems, draftErrs := validateOrderDraftAgainstMenu(*menu, payload.Items)
			if draftErrs != nil && !isEmptyDraftErrors(*draftErrs) {
				writeJSON(
					w,
					http.StatusBadRequest,
					validateOrderDraftResponse{
						OK:              false,
						MenuVersion:     menu.UpdatedAt.Format(time.RFC3339),
						NormalizedItems: normalizedItems,
						Errors:          draftErrs,
					},
				)
				return
			}
			payload.Items = normalizedItems
			totals = computeTotals(payload)
		}

		now := time.Now().UTC()
		expire := now.Add(time.Duration(cfg.OrderTTLDays) * 24 * time.Hour)

		order := orderRecord{
			ID:              generateOrderID(),
			StoreID:         payload.StoreID,
			CallSid:         payload.CallSid,
			Channel:         payload.Channel,
			CustomerName:    payload.CustomerName,
			TenantID:        payload.TenantID,
			CustomerID:      payload.CustomerID,
			CallerID:        payload.CallerID,
			ChannelContact:  payload.ChannelContact,
			Origin:          normalizeOrderOrigin(payload.Origin),
			Notes:           payload.Notes,
			BusinessType:    payload.BusinessType,
			PaymentMethod:   payload.PaymentMethod,
			Items:           payload.Items,
			Fuel:            fuelRecord,
			Status:          statusPending,
			FulfillmentType: fulfillmentType,
			Delivery:        payload.Delivery,
			SubtotalCents:   totals.SubtotalCents,
			TaxCents:        totals.TaxCents,
			FeeCents:        totals.FeeCents,
			DiscountCents:   totals.DiscountCents,
			TotalCents:      totals.TotalCents,
			CreatedAt:       now,
			UpdatedAt:       now,
			ExpireAt:        expire,
		}

		order, err = createOrder(ctx, firestoreClient, order, payload.IdempotencyKey)
		if err != nil {
			if errors.Is(err, errIdempotencyConflict) && payload.IdempotencyKey != "" {
				if existing, fetchErr := fetchOrderByIdempotencyKey(ctx, firestoreClient, payload.IdempotencyKey); fetchErr == nil && existing != nil {
					writeJSON(w, http.StatusOK, existing)
					return
				}
			}
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

	// Business-facing wait time analytics (read-only).
	router.Get("/stores/{storeID}/wait-time/summary", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		handleWaitTimeSummary(ctx, firestoreClient, cfg, waitTimeMetaCache, w, r, storeID)
	})

	router.Get("/stores/{storeID}/wait-time/daily", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		days := parseIntDefault(strings.TrimSpace(r.URL.Query().Get("days")), 7)
		if days < 1 {
			days = 1
		}
		if days > 30 {
			days = 30
		}
		handleWaitTimeDaily(ctx, firestoreClient, cfg, waitTimeMetaCache, w, r, storeID, days)
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
			StoreID:     storeID,
			Items:       menu.Items,
			BundleRules: menu.BundleRules,
			Updated:     menu.UpdatedAt.Format(time.RFC3339),
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
		normalized := normalizeMenuRecord(&payload)
		if normalized != nil {
			payload = *normalized
		}
		if err := validateMenu(payload); err != nil {
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

	// Validate an order draft against the current menu (menu-only + required modifier groups + bundles).
	// Intended for voice agents / tooling.
	router.Post("/stores/{storeID}/orders/validate-draft", func(w http.ResponseWriter, r *http.Request) {
		storeID := chi.URLParam(r, "storeID")
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		var payload validateOrderDraftRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		menu, err := fetchMenuCached(ctx, firestoreClient, storeID)
		if err != nil {
			log.Printf("validate-draft menu fetch failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if menu == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "menu_not_found"})
			return
		}

		normalizedItems, errs := validateOrderDraftAgainstMenu(*menu, payload.Items)
		resp := validateOrderDraftResponse{
			OK:              errs == nil || isEmptyDraftErrors(*errs),
			MenuVersion:     menu.UpdatedAt.Format(time.RFC3339),
			NormalizedItems: normalizedItems,
		}
		if errs != nil && !isEmptyDraftErrors(*errs) {
			resp.Errors = errs
		}
		writeJSON(w, http.StatusOK, resp)
	})

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

	// List group orders by store with optional status filter and pagination.
	router.Get("/stores/{storeID}/group-orders", func(w http.ResponseWriter, r *http.Request) {
		handleStoreGroupOrdersList(w, r, firestoreClient, cfg)
	})

	// Fetch a group order scoped to a store (business app).
	router.Get("/stores/{storeID}/group-orders/{groupOrderId}", func(w http.ResponseWriter, r *http.Request) {
		handleStoreGroupOrderGet(w, r, firestoreClient, cfg)
	})

	// Update order details (items/notes) when order is still editable.
	// Allowed only when status is pending or confirmed.
	router.Patch("/orders/{orderID}", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		var payload struct {
			Items *[]orderItem `json:"items"`
			Notes *string      `json:"notes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.Items == nil && payload.Notes == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
			return
		}
		if payload.Items != nil {
			if err := validateItems(*payload.Items, nil); err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
				return
			}
		}

		updated, err := updateOrderEditableFields(ctx, firestoreClient, orderID, payload.Items, payload.Notes, r.Context(), cfg.RequireAuth)
		if err != nil {
			if errors.Is(err, errOrderNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
				return
			}
			if errors.Is(err, errUnauthorizedStore) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			if errors.Is(err, errOrderLocked) {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order_not_editable"})
				return
			}
			log.Printf("failed updating order: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}

		// Publish updated order payload (best-effort).
		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, *updated); err != nil {
				log.Printf("failed to publish order event: %v", err)
			}
		}

		writeJSON(w, http.StatusOK, updated)
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
			Status     string `json:"status"`
			NotifyMode string `json:"notifyMode"`
			Note       string `json:"note"`
			TemplateID string `json:"templateId"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.Status == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		notifyMode := strings.TrimSpace(payload.NotifyMode)
		if notifyMode == "" {
			notifyMode = notifyModeAuto
		}
		if !isValidNotifyMode(notifyMode) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_notify_mode"})
			return
		}

		updated, err := updateOrderStatus(ctx, firestoreClient, orderID, payload.Status, notifyMode, strings.TrimSpace(payload.Note), strings.TrimSpace(payload.TemplateID), r.Context(), cfg.RequireAuth)
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

	// Refund order payment (card only).
	router.Post("/orders/{orderID}/refund", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		handleOrderRefund(ctx, firestoreClient, cfg, w, r, orderID)
	})

	// Gas station: set pump number (customer-facing).
	router.Patch("/orders/{orderID}/fuel", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		handleFuelPumpUpdate(ctx, firestoreClient, false, w, r, orderID)
	})

	// Gas station: complete fueling (staff action + capture if preauth).
	router.Post("/orders/{orderID}/fuel/complete", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		handleFuelComplete(ctx, firestoreClient, cfg, w, r, orderID)
	})

	// Patch delivery fields (assignment / tracking / status summary).
	// Intended for internal services (dispatch-service, delivery-service) and backoffice tooling.
	router.Patch("/orders/{orderID}/delivery", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		var payload orderDeliveryPatch
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.AssignedDriverID == nil &&
			payload.AssignedRouteID == nil &&
			payload.AssignmentStatus == nil &&
			payload.ProviderDeliveryID == nil &&
			payload.TrackingURL == nil &&
			payload.DeliveryStatusSummary == nil &&
			payload.Quote == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
			return
		}

		updated, err := updateOrderDelivery(ctx, firestoreClient, orderID, payload, r.Context(), cfg.RequireAuth)
		if err != nil {
			if errors.Is(err, errOrderNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
				return
			}
			if errors.Is(err, errUnauthorizedStore) {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
				return
			}
			if errors.Is(err, errNotDeliveryOrder) {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "not_delivery_order"})
				return
			}
			if errors.Is(err, errOrderLocked) {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "order_not_editable"})
				return
			}
			log.Printf("failed updating delivery: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}

		// Publish updated order payload (best-effort).
		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, *updated); err != nil {
				log.Printf("failed to publish order event: %v", err)
			}
		}
		writeJSON(w, http.StatusOK, updated)
	})

	// Trigger customer communications without changing order status (e.g. "delay" notice).
	router.Post("/orders/{orderID}/customer-comms", func(w http.ResponseWriter, r *http.Request) {
		orderID := chi.URLParam(r, "orderID")
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		var payload struct {
			Kind       string `json:"kind"`
			NotifyMode string `json:"notifyMode"`
			Note       string `json:"note"`
			TemplateID string `json:"templateId"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		kind := strings.TrimSpace(payload.Kind)
		if kind == "" {
			kind = "delay"
		}
		if kind != "delay" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_kind"})
			return
		}

		notifyMode := strings.TrimSpace(payload.NotifyMode)
		if notifyMode == "" {
			notifyMode = notifyModeAuto
		}
		if !isValidNotifyMode(notifyMode) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_notify_mode"})
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

		evt := orderCustomerCommsEvent{
			Kind:  "order_customer_comms",
			Order: *record,
			Comms: customerCommsPayload{
				Kind:       kind,
				NotifyMode: notifyMode,
				Note:       strings.TrimSpace(payload.Note),
				TemplateID: strings.TrimSpace(payload.TemplateID),
			},
			CreatedAt: time.Now().UTC(),
		}
		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderCustomerCommsEvent(ctx, pubsubClient, cfg.OrdersTopic, evt); err != nil {
				log.Printf("failed to publish customer comms event: %v", err)
				writeJSON(w, http.StatusBadGateway, map[string]string{"error": "publish_failed"})
				return
			}
		}

		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
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
		Port:                  port,
		Environment:           stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:             stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials:           stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		OrdersTopic:           stringOrDefault(values["PUBSUB_TOPIC_ORDERS"], ""),
		MenuUpdatesSub:        stringOrDefault(values["PUBSUB_SUBSCRIPTION_MENU_UPDATES"], ""),
		RequireAuth:           stringOrDefault(values["REQUIRE_AUTH"], "true") == "true",
		OrderTTLDays:          intOrDefault(values["ORDER_TTL_DAYS"], 30),
		APIKey:                stringOrDefault(values["ORDER_SERVICE_API_KEY"], os.Getenv("ORDER_SERVICE_API_KEY")),
		InternalAuthAudience:  strings.TrimSpace(os.Getenv("INTERNAL_AUTH_AUDIENCE")),
		InternalAllowedEmails: splitCSV(os.Getenv("INTERNAL_ALLOWED_EMAILS")),
		WaitTimeMinSamples:    parseIntDefault(strings.TrimSpace(os.Getenv("WAIT_TIME_MIN_SAMPLES_FOR_MEDIAN")), 10),
		PaymentsServiceURL: strings.TrimSpace(
			stringOrDefault(values["PAYMENTS_SERVICE_URL"], os.Getenv("PAYMENTS_SERVICE_URL")),
		),
	}, nil
}

func splitCSV(v string) []string {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	parts := strings.Split(v, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		s := strings.TrimSpace(p)
		if s != "" {
			out = append(out, s)
		}
	}
	return out
}

func allowedOrigins() []string {
	defaults := []string{
		"http://localhost:3000",
		"http://localhost:4000",
		"http://localhost:4001",
		"http://localhost:8080",
		"http://localhost:65269", // Flutter web dev server
		"http://localhost:*",
		"http://127.0.0.1:4000",
		"http://127.0.0.1:*",
		"https://order-service-f2qwyitacq-uc.a.run.app",
	}
	if v := os.Getenv("CORS_ORIGINS"); v != "" {
		parts := strings.Split(v, ",")
		seen := map[string]struct{}{}
		out := make([]string, 0, len(parts)+len(defaults))
		for _, part := range parts {
			origin := strings.TrimSpace(part)
			if origin == "" {
				continue
			}
			if origin == "*" {
				return []string{"*"}
			}
			if _, ok := seen[origin]; ok {
				continue
			}
			seen[origin] = struct{}{}
			out = append(out, origin)
		}
		for _, origin := range defaults {
			if _, ok := seen[origin]; ok {
				continue
			}
			seen[origin] = struct{}{}
			out = append(out, origin)
		}
		return out
	}
	return defaults
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

func createOrder(ctx context.Context, client *cloudfirestore.Client, order orderRecord, idempotencyKey string) (orderRecord, error) {
	var displayNumber string
	err := client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		if idempotencyKey != "" {
			// reserve idempotency key
			idDoc := client.Collection(idempotencyCollection).Doc(idempotencyKey)
			// if exists, treat as already processed
			_, err := tx.Get(idDoc)
			if err == nil {
				return errIdempotencyConflict
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

		nextNumber, err := nextOrderDisplayNumber(ctx, tx, client, order.StoreID, order.CreatedAt)
		if err != nil {
			return err
		}
		displayNumber = nextNumber
		record := order
		record.DisplayNumber = displayNumber

		doc := client.Collection(ordersCollection).Doc(order.ID)
		if err := tx.Create(doc, record); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return orderRecord{}, err
	}
	order.DisplayNumber = displayNumber
	return order, nil
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

func publishOrderCustomerCommsEvent(ctx context.Context, client *cloudpubsub.Client, topicID string, evt orderCustomerCommsEvent) error {
	topic := client.Topic(topicID)
	payload, err := json.Marshal(evt)
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

type validateOrderDraftRequest struct {
	Items []orderItem `json:"items"`
}

type validateOrderDraftResponse struct {
	OK              bool                      `json:"ok"`
	MenuVersion     string                    `json:"menuVersion,omitempty"`
	NormalizedItems []orderItem               `json:"normalizedItems,omitempty"`
	Errors          *validateOrderDraftErrors `json:"errors,omitempty"`
}

type validateOrderDraftErrors struct {
	InvalidItems            []invalidItemError            `json:"invalidItems,omitempty"`
	MissingModifierGroups   []missingModifierGroupError   `json:"missingGroups,omitempty"`
	InvalidModifierChoices  []invalidModifierChoiceError  `json:"invalidModifierChoices,omitempty"`
	MissingBundleComponents []missingBundleComponentError `json:"missingBundleComponents,omitempty"`
	InvalidBundles          []invalidBundleError          `json:"invalidBundles,omitempty"`
}

type menuItemMatch struct {
	ItemID     string `json:"itemId"`
	Name       string `json:"name"`
	Category   string `json:"category"`
	PriceCents int64  `json:"priceCents"`
	Available  bool   `json:"available"`
}

type invalidItemError struct {
	ItemID      string          `json:"itemId,omitempty"`
	Name        string          `json:"name,omitempty"`
	Reason      string          `json:"reason"`
	BestMatches []menuItemMatch `json:"bestMatches,omitempty"`
}

type missingModifierGroupError struct {
	ItemID        string           `json:"itemId"`
	ItemName      string           `json:"itemName"`
	GroupID       string           `json:"groupId"`
	GroupName     string           `json:"groupName"`
	Required      bool             `json:"required"`
	MinSelections int              `json:"minSelections"`
	MaxSelections int              `json:"maxSelections"`
	Options       []modifierOption `json:"options"`
}

type invalidModifierChoiceError struct {
	ItemID   string `json:"itemId"`
	ItemName string `json:"itemName"`
	GroupID  string `json:"groupId,omitempty"`
	OptionID string `json:"optionId,omitempty"`
	Name     string `json:"name,omitempty"`
	Reason   string `json:"reason"`
}

type missingBundleComponentError struct {
	BundleID        string          `json:"bundleId"`
	DisplayName     string          `json:"displayName"`
	Role            string          `json:"role"`
	AllowedCategory string          `json:"category,omitempty"`
	AllowedItems    []menuItemMatch `json:"allowedItems,omitempty"`
}

type invalidBundleError struct {
	BundleID string `json:"bundleId"`
	Reason   string `json:"reason"`
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
		modifiersSum := orderItemModifiersSum(item)
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

func orderItemModifiersSum(item orderItem) int64 {
	if len(item.ModifierSelections) > 0 {
		var sum int64
		for _, sel := range item.ModifierSelections {
			sum += sel.PriceCents
		}
		return sum
	}
	var sum int64
	for _, mod := range item.Modifiers {
		sum += mod.Price
	}
	return sum
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
				// Validate modifier selections against structured groups (preferred) or legacy modifiers.
				groups := normalizedModifierGroups(m)
				if len(item.ModifierSelections) > 0 {
					groupIndex := map[string]modifierGroup{}
					for _, g := range groups {
						groupIndex[g.ID] = g
					}
					for _, sel := range item.ModifierSelections {
						gid := strings.TrimSpace(sel.GroupID)
						oid := strings.TrimSpace(sel.OptionID)
						if gid == "" || oid == "" {
							return errors.New("modifier_selection_missing_fields")
						}
						g, ok := groupIndex[gid]
						if !ok {
							return fmt.Errorf("modifier_group_not_in_menu:%s", gid)
						}
						found := false
						for _, opt := range g.Options {
							if opt.ID == oid {
								found = true
								break
							}
						}
						if !found {
							return fmt.Errorf("modifier_option_not_in_menu:%s", oid)
						}
					}
				} else if len(item.Modifiers) > 0 {
					// Legacy selections by name: accept if the name matches any option across all groups.
					optNames := map[string]bool{}
					for _, g := range groups {
						for _, opt := range g.Options {
							optNames[opt.Name] = true
						}
					}
					for _, sel := range item.Modifiers {
						if !optNames[sel.Name] {
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

func isEmptyDraftErrors(errs validateOrderDraftErrors) bool {
	return len(errs.InvalidItems) == 0 &&
		len(errs.MissingModifierGroups) == 0 &&
		len(errs.InvalidModifierChoices) == 0 &&
		len(errs.MissingBundleComponents) == 0 &&
		len(errs.InvalidBundles) == 0
}

func validateOrderDraftAgainstMenu(menu menuRecord, items []orderItem) ([]orderItem, *validateOrderDraftErrors) {
	errs := &validateOrderDraftErrors{}

	menuItems := menu.Items
	itemIndex := map[string]menuItem{}
	for _, it := range menuItems {
		itemIndex[it.ID] = normalizeMenuItem(it)
	}

	normalized := make([]orderItem, 0, len(items))
	for _, it := range items {
		itemID := strings.TrimSpace(it.ItemID)
		if itemID == "" {
			errs.InvalidItems = append(errs.InvalidItems, invalidItemError{
				ItemID: itemID,
				Name:   strings.TrimSpace(it.Name),
				Reason: "missing_item_id",
			})
			continue
		}
		menuItem, ok := itemIndex[itemID]
		if !ok {
			errs.InvalidItems = append(errs.InvalidItems, invalidItemError{
				ItemID:      itemID,
				Name:        strings.TrimSpace(it.Name),
				Reason:      "item_not_in_menu",
				BestMatches: bestMenuMatches(menuItems, strings.TrimSpace(it.Name), 5),
			})
			continue
		}
		if !menuItem.Available {
			errs.InvalidItems = append(errs.InvalidItems, invalidItemError{
				ItemID: itemID,
				Name:   strings.TrimSpace(it.Name),
				Reason: "item_unavailable",
			})
			continue
		}
		if it.Quantity <= 0 {
			errs.InvalidItems = append(errs.InvalidItems, invalidItemError{
				ItemID: itemID,
				Name:   strings.TrimSpace(it.Name),
				Reason: "invalid_quantity",
			})
			continue
		}

		// Normalize name/category/pricing from menu.
		out := it
		out.Name = menuItem.Name
		out.Category = menuItem.Category
		if out.PriceCents == 0 {
			out.PriceCents = menuItem.PriceCents
		}
		// If this item triggers a bundle rule and the draft didn't specify a bundle, infer it.
		if strings.TrimSpace(out.BundleID) == "" {
			if inferred := inferBundleID(menu.BundleRules, itemID, menuItem.Category); inferred != "" {
				out.BundleID = inferred
				if strings.TrimSpace(out.BundleRole) == "" {
					out.BundleRole = "main"
				}
			}
		}

		groups := normalizedModifierGroups(menuItem)
		if len(out.ModifierSelections) == 0 && len(out.Modifiers) > 0 {
			// Map legacy modifiers (by name) to structured selections if possible.
			for _, legacySel := range out.Modifiers {
				mapped := false
				for _, g := range groups {
					for _, opt := range g.Options {
						if strings.EqualFold(strings.TrimSpace(opt.Name), strings.TrimSpace(legacySel.Name)) {
							out.ModifierSelections = append(out.ModifierSelections, modifierSelectionV2{
								GroupID:    g.ID,
								OptionID:   opt.ID,
								Name:       opt.Name,
								PriceCents: opt.PriceCents,
							})
							mapped = true
							break
						}
					}
					if mapped {
						break
					}
				}
				if !mapped {
					errs.InvalidModifierChoices = append(errs.InvalidModifierChoices, invalidModifierChoiceError{
						ItemID:   itemID,
						ItemName: menuItem.Name,
						Name:     strings.TrimSpace(legacySel.Name),
						Reason:   "modifier_not_in_menu",
					})
				}
			}
		}

		// Validate modifier selections and enforce required/min/max.
		groupIndex := map[string]modifierGroup{}
		for _, g := range groups {
			groupIndex[g.ID] = g
		}
		counts := map[string]int{}
		for si := range out.ModifierSelections {
			sel := &out.ModifierSelections[si]
			gid := strings.TrimSpace(sel.GroupID)
			oid := strings.TrimSpace(sel.OptionID)
			if gid == "" || oid == "" {
				errs.InvalidModifierChoices = append(errs.InvalidModifierChoices, invalidModifierChoiceError{
					ItemID:   itemID,
					ItemName: menuItem.Name,
					GroupID:  gid,
					OptionID: oid,
					Name:     strings.TrimSpace(sel.Name),
					Reason:   "modifier_selection_missing_fields",
				})
				continue
			}
			g, ok := groupIndex[gid]
			if !ok {
				errs.InvalidModifierChoices = append(errs.InvalidModifierChoices, invalidModifierChoiceError{
					ItemID:   itemID,
					ItemName: menuItem.Name,
					GroupID:  gid,
					OptionID: oid,
					Name:     strings.TrimSpace(sel.Name),
					Reason:   "modifier_group_not_in_menu",
				})
				continue
			}
			found := false
			var optPrice int64
			var optName string
			for _, opt := range g.Options {
				if opt.ID == oid {
					found = true
					optPrice = opt.PriceCents
					optName = opt.Name
					break
				}
			}
			if !found {
				errs.InvalidModifierChoices = append(errs.InvalidModifierChoices, invalidModifierChoiceError{
					ItemID:   itemID,
					ItemName: menuItem.Name,
					GroupID:  gid,
					OptionID: oid,
					Name:     strings.TrimSpace(sel.Name),
					Reason:   "modifier_option_not_in_menu",
				})
				continue
			}
			counts[gid]++
			// Normalize selection name/price from menu.
			if optName != "" {
				sel.Name = optName
			}
			if sel.PriceCents == 0 {
				sel.PriceCents = optPrice
			}
		}

		for _, g := range groups {
			count := counts[g.ID]
			minSel := g.MinSelections
			if g.Required && minSel == 0 {
				minSel = 1
			}
			if count < minSel {
				errs.MissingModifierGroups = append(errs.MissingModifierGroups, missingModifierGroupError{
					ItemID:        itemID,
					ItemName:      menuItem.Name,
					GroupID:       g.ID,
					GroupName:     g.Name,
					Required:      g.Required,
					MinSelections: minSel,
					MaxSelections: g.MaxSelections,
					Options:       g.Options,
				})
			}
			if g.MaxSelections > 0 && count > g.MaxSelections {
				errs.InvalidModifierChoices = append(errs.InvalidModifierChoices, invalidModifierChoiceError{
					ItemID:   itemID,
					ItemName: menuItem.Name,
					GroupID:  g.ID,
					Reason:   "too_many_selections",
				})
			}
		}

		normalized = append(normalized, out)
	}

	// Bundle validation (combo builder).
	if len(menu.BundleRules) > 0 {
		validateBundles(menu, normalized, errs)
	}

	return normalized, errs
}

func validateBundles(menu menuRecord, items []orderItem, errs *validateOrderDraftErrors) {
	if errs == nil {
		return
	}
	ruleIndex := map[string]bundleRule{}
	for _, r := range menu.BundleRules {
		ruleIndex[strings.TrimSpace(r.BundleID)] = r
	}
	byBundle := map[string][]orderItem{}
	for _, it := range items {
		bid := strings.TrimSpace(it.BundleID)
		if bid == "" {
			continue
		}
		byBundle[bid] = append(byBundle[bid], it)
	}
	if len(byBundle) == 0 {
		return
	}

	itemIndex := map[string]menuItem{}
	for _, it := range menu.Items {
		itemIndex[it.ID] = it
	}

	for bundleID, bundleItems := range byBundle {
		rule, ok := ruleIndex[bundleID]
		if !ok {
			errs.InvalidBundles = append(errs.InvalidBundles, invalidBundleError{BundleID: bundleID, Reason: "bundle_rule_not_found"})
			continue
		}
		rolePresent := map[string]bool{}
		for _, bi := range bundleItems {
			role := strings.TrimSpace(strings.ToLower(bi.BundleRole))
			if role != "" {
				rolePresent[role] = true
			}
		}
		missingKey := map[string]bool{} // itemId:groupId
		for _, comp := range rule.Components {
			role := strings.TrimSpace(strings.ToLower(comp.Role))
			if role == "" {
				continue
			}
			if rolePresent[role] {
				// Validate allowedness.
				for _, bi := range bundleItems {
					if strings.TrimSpace(strings.ToLower(bi.BundleRole)) != role {
						continue
					}
					mi, ok := itemIndex[bi.ItemID]
					if !ok {
						continue
					}
					if !bundleComponentAllowsItem(comp, mi) {
						errs.InvalidBundles = append(errs.InvalidBundles, invalidBundleError{BundleID: bundleID, Reason: "bundle_component_item_not_allowed"})
						break
					}
					// Enforce bundle component required groups (even if the item itself doesn't mark them required).
					if len(comp.RequiredGroupIDs) > 0 {
						groups := normalizedModifierGroups(normalizeMenuItem(mi))
						groupIndex := map[string]modifierGroup{}
						for _, g := range groups {
							groupIndex[g.ID] = g
						}
						selCounts := map[string]int{}
						for _, sel := range bi.ModifierSelections {
							selCounts[strings.TrimSpace(sel.GroupID)]++
						}
						for _, gid := range comp.RequiredGroupIDs {
							gid = strings.TrimSpace(gid)
							if gid == "" {
								continue
							}
							if selCounts[gid] > 0 {
								continue
							}
							g, ok := groupIndex[gid]
							if !ok {
								continue
							}
							k := bi.ItemID + ":" + gid
							if missingKey[k] {
								continue
							}
							missingKey[k] = true
							errs.MissingModifierGroups = append(errs.MissingModifierGroups, missingModifierGroupError{
								ItemID:        bi.ItemID,
								ItemName:      strings.TrimSpace(mi.Name),
								GroupID:       g.ID,
								GroupName:     g.Name,
								Required:      true,
								MinSelections: 1,
								MaxSelections: g.MaxSelections,
								Options:       g.Options,
							})
						}
					}
				}
				continue
			}
			errs.MissingBundleComponents = append(errs.MissingBundleComponents, missingBundleComponentError{
				BundleID:        bundleID,
				DisplayName:     rule.DisplayName,
				Role:            role,
				AllowedCategory: strings.TrimSpace(comp.AllowedCategory),
				AllowedItems:    allowedItemsForBundleComponent(comp, menu.Items, 12),
			})
		}
	}
}

func inferBundleID(rules []bundleRule, itemID string, category string) string {
	itemID = strings.TrimSpace(itemID)
	if itemID == "" || len(rules) == 0 {
		return ""
	}
	for _, r := range rules {
		if strings.TrimSpace(r.TriggerItemID) != "" && strings.TrimSpace(r.TriggerItemID) == itemID {
			return strings.TrimSpace(r.BundleID)
		}
	}
	// Category triggers are only safe to infer if exactly one rule matches.
	cat := strings.TrimSpace(category)
	if cat == "" {
		return ""
	}
	var match string
	for _, r := range rules {
		if strings.TrimSpace(r.TriggerCategory) != "" && strings.EqualFold(strings.TrimSpace(r.TriggerCategory), cat) {
			if match != "" {
				return ""
			}
			match = strings.TrimSpace(r.BundleID)
		}
	}
	return match
}

func bundleComponentAllowsItem(comp bundleComponent, item menuItem) bool {
	if len(comp.AllowedItemIDs) > 0 {
		for _, id := range comp.AllowedItemIDs {
			if id == item.ID {
				return true
			}
		}
	}
	if strings.TrimSpace(comp.AllowedCategory) != "" && strings.EqualFold(strings.TrimSpace(comp.AllowedCategory), strings.TrimSpace(item.Category)) {
		return true
	}
	return false
}

func allowedItemsForBundleComponent(comp bundleComponent, items []menuItem, limit int) []menuItemMatch {
	out := []menuItemMatch{}
	if limit <= 0 {
		limit = 12
	}
	if len(comp.AllowedItemIDs) > 0 {
		allowed := map[string]bool{}
		for _, id := range comp.AllowedItemIDs {
			allowed[id] = true
		}
		for _, it := range items {
			if !allowed[it.ID] {
				continue
			}
			out = append(out, menuItemMatchFromMenuItem(it))
			if len(out) >= limit {
				break
			}
		}
		return out
	}
	cat := strings.TrimSpace(comp.AllowedCategory)
	if cat == "" {
		return out
	}
	for _, it := range items {
		if strings.EqualFold(strings.TrimSpace(it.Category), cat) {
			out = append(out, menuItemMatchFromMenuItem(it))
			if len(out) >= limit {
				break
			}
		}
	}
	return out
}

func bestMenuMatches(menuItems []menuItem, query string, limit int) []menuItemMatch {
	q := strings.TrimSpace(strings.ToLower(query))
	if q == "" || limit <= 0 {
		return nil
	}
	out := []menuItemMatch{}
	for _, it := range menuItems {
		name := strings.ToLower(strings.TrimSpace(it.Name))
		cat := strings.ToLower(strings.TrimSpace(it.Category))
		if strings.Contains(name, q) || strings.Contains(cat, q) {
			out = append(out, menuItemMatchFromMenuItem(it))
			if len(out) >= limit {
				break
			}
		}
	}
	return out
}

func menuItemMatchFromMenuItem(it menuItem) menuItemMatch {
	return menuItemMatch{
		ItemID:     it.ID,
		Name:       it.Name,
		Category:   it.Category,
		PriceCents: it.PriceCents,
		Available:  it.Available,
	}
}

var errInvalidTransition = errors.New("invalid_status_transition")
var errOrderNotFound = errors.New("order_not_found")
var errUnauthorizedStore = errors.New("unauthorized_store")
var errOrderLocked = errors.New("order_not_editable")
var errNotDeliveryOrder = errors.New("not_delivery_order")
var errIdempotencyConflict = errors.New("idempotency_conflict")

func isValidNotifyMode(v string) bool {
	switch v {
	case notifyModeAuto, notifyModeSMS, notifyModeCall, notifyModeNone:
		return true
	default:
		return false
	}
}

func authUID(ctx context.Context) string {
	val := ctx.Value(authContextKey)
	if val == nil {
		return ""
	}
	ac, ok := val.(authContext)
	if !ok {
		return ""
	}
	return strings.TrimSpace(ac.UID)
}

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

func updateOrderStatus(ctx context.Context, client *cloudfirestore.Client, orderID string, newStatus string, notifyMode string, note string, templateID string, reqCtx context.Context, requireAuth bool) (*orderRecord, error) {
	if newStatus == "" {
		return nil, errInvalidTransition
	}
	if notifyMode == "" {
		notifyMode = notifyModeAuto
	}
	if !isValidNotifyMode(notifyMode) {
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

		now := time.Now().UTC()
		record.StatusChange = &orderStatusChange{
			PreviousStatus: record.Status,
			NewStatus:      newStatus,
			ChangedAt:      now,
			ChangedBy:      authUID(reqCtx),
			NotifyMode:     notifyMode,
			Note:           strings.TrimSpace(note),
			TemplateID:     strings.TrimSpace(templateID),
		}
		// Persist lifecycle timestamps on first transition to each state.
		switch newStatus {
		case statusConfirmed:
			if record.ConfirmedAt == nil {
				t := now
				record.ConfirmedAt = &t
			}
		case statusReady:
			if record.ReadyAt == nil {
				t := now
				record.ReadyAt = &t
			}
		case statusCompleted:
			if record.CompletedAt == nil {
				t := now
				record.CompletedAt = &t
			}
		case statusCancelled:
			if record.CancelledAt == nil {
				t := now
				record.CancelledAt = &t
			}
		}
		record.Status = newStatus
		record.UpdatedAt = now
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

func updateOrderDelivery(
	ctx context.Context,
	client *cloudfirestore.Client,
	orderID string,
	patch orderDeliveryPatch,
	reqCtx context.Context,
	requireAuth bool,
) (*orderRecord, error) {
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
		if strings.ToLower(strings.TrimSpace(record.FulfillmentType)) != "delivery" {
			return errNotDeliveryOrder
		}

		if record.Delivery == nil {
			record.Delivery = &orderDelivery{}
		}

		if patch.AssignedDriverID != nil {
			record.Delivery.AssignedDriverID = strings.TrimSpace(*patch.AssignedDriverID)
		}
		if patch.AssignedRouteID != nil {
			record.Delivery.AssignedRouteID = strings.TrimSpace(*patch.AssignedRouteID)
		}
		if patch.AssignmentStatus != nil {
			record.Delivery.AssignmentStatus = strings.ToLower(strings.TrimSpace(*patch.AssignmentStatus))
		}
		if patch.ProviderDeliveryID != nil {
			record.Delivery.ProviderDeliveryID = strings.TrimSpace(*patch.ProviderDeliveryID)
		}
		if patch.TrackingURL != nil {
			record.Delivery.TrackingURL = strings.TrimSpace(*patch.TrackingURL)
		}
		if patch.DeliveryStatusSummary != nil {
			record.Delivery.DeliveryStatusSummary = strings.TrimSpace(*patch.DeliveryStatusSummary)
		}
		if patch.Quote != nil {
			if record.Delivery.Quote == nil {
				record.Delivery.Quote = &deliveryQuote{}
			}
			if patch.Quote.Provider != nil {
				record.Delivery.Quote.Provider = strings.TrimSpace(*patch.Quote.Provider)
			}
			if patch.Quote.ProviderFeeCents != nil {
				record.Delivery.Quote.ProviderFeeCents = *patch.Quote.ProviderFeeCents
			}
			if patch.Quote.DropoffEtaMinutes != nil {
				record.Delivery.Quote.DropoffEtaMinutes = *patch.Quote.DropoffEtaMinutes
			}
			if patch.Quote.Currency != nil {
				record.Delivery.Quote.Currency = strings.TrimSpace(*patch.Quote.Currency)
			}
			if patch.Quote.QuoteExpiresAt != nil {
				ts := strings.TrimSpace(*patch.Quote.QuoteExpiresAt)
				if ts == "" {
					record.Delivery.Quote.QuoteExpiresAt = nil
				} else if t, err := time.Parse(time.RFC3339, ts); err == nil {
					tt := t
					record.Delivery.Quote.QuoteExpiresAt = &tt
				} else {
					return errInvalidTransition
				}
			}
		}

		record.UpdatedAt = time.Now().UTC()
		return tx.Set(docRef, record)
	})
	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
}

func updateOrderEditableFields(
	ctx context.Context,
	client *cloudfirestore.Client,
	orderID string,
	items *[]orderItem,
	notes *string,
	reqCtx context.Context,
	requireAuth bool,
) (*orderRecord, error) {
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

		if record.Status != statusPending && record.Status != statusConfirmed {
			return errOrderLocked
		}

		changed := false
		if items != nil {
			record.Items = *items
			// Recompute totals, preserving existing taxes/fees/discounts.
			t := computeTotals(orderRequest{
				Items:         record.Items,
				TaxCents:      record.TaxCents,
				FeeCents:      record.FeeCents,
				DiscountCents: record.DiscountCents,
			})
			record.SubtotalCents = t.SubtotalCents
			record.TotalCents = t.TotalCents
			changed = true
		}
		if notes != nil {
			record.Notes = strings.TrimSpace(*notes)
			changed = true
		}
		if !changed {
			return nil
		}
		record.UpdatedAt = time.Now().UTC()
		return tx.Set(docRef, record)
	})

	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
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

// apiKeyOrFirebaseMiddleware allows requests with a matching X-API-Key header to bypass Firebase auth.
// If the API key is missing or wrong, it supports internal Google OIDC ID tokens (IAM-style),
// and then falls back to Firebase ID token verification when required.
func apiKeyOrFirebaseMiddleware(
	apiKey string,
	client tokenVerifier,
	requireAuth bool,
	internalAudience string,
	internalAllowedEmails []string,
) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Allow CORS preflight without auth.
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}
			if isHealthCheckPath(r.URL.Path) {
				next.ServeHTTP(w, r)
				return
			}

			// API key path (shared secret for agent tools).
			if apiKey != "" {
				if key := r.Header.Get("X-API-Key"); key != "" && key == apiKey {
					ctx := context.WithValue(r.Context(), authContextKey, authContext{
						UID:      "api-key",
						Role:     "api-key",
						StoreIDs: []string{}, // empty => full access
					})
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}

			// If auth not required, continue.
			if !requireAuth {
				next.ServeHTTP(w, r)
				return
			}

			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			if tokenString == authHeader { // no prefix found
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
				return
			}

			// Firebase ID token path.
			if client != nil {
				if token, err := client.VerifyIDToken(r.Context(), tokenString); err == nil {
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
					return
				}
			}

			// Internal IAM-style auth: Google OIDC ID token minted for this service.
			if internalAudience != "" {
				if ok, ac := tryGoogleIDTokenAuth(r.Context(), tokenString, internalAudience, internalAllowedEmails); ok {
					ctx := context.WithValue(r.Context(), authContextKey, ac)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}

			// If Firebase isn't configured and internal auth isn't configured, we can't authenticate.
			if client == nil && internalAudience == "" {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
				return
			}
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		})
	}
}

func tryGoogleIDTokenAuth(ctx context.Context, tokenString, audience string, allowedEmails []string) (bool, authContext) {
	payload, err := idtoken.Validate(ctx, tokenString, audience)
	if err != nil {
		return false, authContext{}
	}
	email := ""
	if v, ok := payload.Claims["email"]; ok {
		if s, ok := v.(string); ok {
			email = s
		}
	}
	email = strings.TrimSpace(email)
	if email == "" {
		// Be strict to avoid accidental broad allow.
		return false, authContext{}
	}
	if len(allowedEmails) > 0 {
		ok := false
		for _, a := range allowedEmails {
			if strings.EqualFold(strings.TrimSpace(a), email) {
				ok = true
				break
			}
		}
		if !ok {
			return false, authContext{}
		}
	}
	return true, authContext{
		UID:      email,
		Role:     "internal",
		StoreIDs: []string{}, // full access (system)
	}
}

func firebaseAuthMiddleware(client tokenVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Allow CORS preflight without auth.
			if r.Method == http.MethodOptions {
				next.ServeHTTP(w, r)
				return
			}
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
	n := normalizeMenuRecord(&menu)
	return n, nil
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
		for _, g := range normalizedModifierGroups(item) {
			if strings.TrimSpace(g.ID) == "" || strings.TrimSpace(g.Name) == "" {
				return errors.New("menu_modifier_group_missing_fields")
			}
			if g.MinSelections < 0 || g.MaxSelections < 0 {
				return errors.New("menu_modifier_group_invalid_limits")
			}
			if g.Required && g.MinSelections == 0 {
				return errors.New("menu_modifier_group_required_min_zero")
			}
			if g.MaxSelections < g.MinSelections {
				return errors.New("menu_modifier_group_invalid_min_max")
			}
			if len(g.Options) == 0 && (g.MinSelections > 0 || g.MaxSelections > 0) {
				return errors.New("menu_modifier_group_no_options")
			}
			if g.MaxSelections > len(g.Options) {
				return errors.New("menu_modifier_group_max_exceeds_options")
			}
			optIDs := map[string]bool{}
			for _, opt := range g.Options {
				if strings.TrimSpace(opt.ID) == "" || strings.TrimSpace(opt.Name) == "" {
					return errors.New("menu_modifier_option_missing_fields")
				}
				if opt.PriceCents < 0 {
					return errors.New("menu_modifier_option_invalid_price")
				}
				if optIDs[opt.ID] {
					return errors.New("menu_modifier_option_duplicate_id")
				}
				optIDs[opt.ID] = true
			}
		}
	}
	return nil
}

func validateMenu(menu menuRecord) error {
	if err := validateMenuItems(menu.Items); err != nil {
		return err
	}
	if err := validateBundleRules(menu.BundleRules, menu.Items); err != nil {
		return err
	}
	return nil
}

func validateBundleRules(rules []bundleRule, items []menuItem) error {
	if len(rules) == 0 {
		return nil
	}
	itemIDs := map[string]bool{}
	categories := map[string]bool{}
	for _, it := range items {
		itemIDs[it.ID] = true
		if it.Category != "" {
			categories[it.Category] = true
		}
	}
	seen := map[string]bool{}
	for _, r := range rules {
		if strings.TrimSpace(r.BundleID) == "" || strings.TrimSpace(r.DisplayName) == "" {
			return errors.New("bundle_rule_missing_fields")
		}
		if seen[r.BundleID] {
			return errors.New("bundle_rule_duplicate_id")
		}
		seen[r.BundleID] = true
		if strings.TrimSpace(r.TriggerItemID) == "" && strings.TrimSpace(r.TriggerCategory) == "" {
			return errors.New("bundle_rule_missing_trigger")
		}
		if r.TriggerItemID != "" && !itemIDs[r.TriggerItemID] {
			return errors.New("bundle_rule_trigger_item_not_in_menu")
		}
		if r.TriggerCategory != "" && !categories[r.TriggerCategory] {
			// Allow defining categories not currently present (for future menu changes) but avoid typos in empty menus.
			if len(items) > 0 {
				return errors.New("bundle_rule_trigger_category_not_in_menu")
			}
		}
		if len(r.Components) == 0 {
			return errors.New("bundle_rule_components_required")
		}
		for _, c := range r.Components {
			if strings.TrimSpace(c.Role) == "" {
				return errors.New("bundle_component_missing_role")
			}
			if len(c.AllowedItemIDs) == 0 && strings.TrimSpace(c.AllowedCategory) == "" {
				return errors.New("bundle_component_missing_allowed")
			}
			for _, id := range c.AllowedItemIDs {
				if strings.TrimSpace(id) == "" {
					return errors.New("bundle_component_invalid_item_id")
				}
			}
		}
	}
	return nil
}

func upsertMenu(ctx context.Context, client *cloudfirestore.Client, menu menuRecord) error {
	n := normalizeMenuRecord(&menu)
	doc := client.Collection(menusCollection).Doc(menu.StoreID)
	_, err := doc.Set(ctx, n)
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
				ItemID:             item.ItemID,
				Name:               m.Name,
				Category:           m.Category,
				Quantity:           item.Quantity,
				PriceCents:         price,
				Modifiers:          item.Modifiers,
				ModifierSelections: item.ModifierSelections,
				BundleID:           item.BundleID,
				BundleRole:         item.BundleRole,
			}
		} else {
			enriched[i] = item
		}
	}
	return enriched
}

func normalizeMenuRecord(menu *menuRecord) *menuRecord {
	if menu == nil {
		return nil
	}
	out := *menu
	out.Items = make([]menuItem, len(menu.Items))
	for i := range menu.Items {
		out.Items[i] = normalizeMenuItem(menu.Items[i])
	}
	if menu.BundleRules != nil {
		out.BundleRules = append([]bundleRule(nil), menu.BundleRules...)
	}
	return &out
}

func normalizeMenuItem(item menuItem) menuItem {
	item.ID = strings.TrimSpace(item.ID)
	item.Name = strings.TrimSpace(item.Name)
	item.Category = strings.TrimSpace(item.Category)
	// Ensure groups exist (derive from legacy modifiers if needed).
	item.ModifierGroups = normalizedModifierGroups(item)
	// Fill missing IDs for groups/options (stable, derived from names).
	seenGroupIDs := map[string]bool{}
	for gi := range item.ModifierGroups {
		g := &item.ModifierGroups[gi]
		if strings.TrimSpace(g.ID) == "" {
			g.ID = stableSlugID(g.Name)
		}
		base := g.ID
		for seenGroupIDs[g.ID] {
			g.ID = base + "-1"
			base = g.ID
		}
		seenGroupIDs[g.ID] = true

		seenOptIDs := map[string]bool{}
		for oi := range g.Options {
			opt := &g.Options[oi]
			if strings.TrimSpace(opt.ID) == "" {
				opt.ID = stableSlugID(opt.Name)
			}
			obase := opt.ID
			for seenOptIDs[opt.ID] {
				opt.ID = obase + "-1"
				obase = opt.ID
			}
			seenOptIDs[opt.ID] = true
		}
		// Default maxSelections for optional groups if not set.
		if g.MaxSelections == 0 && len(g.Options) > 0 {
			g.MaxSelections = len(g.Options)
		}
	}
	return item
}

func normalizedModifierGroups(item menuItem) []modifierGroup {
	if len(item.ModifierGroups) > 0 {
		return item.ModifierGroups
	}
	if len(item.Modifiers) == 0 {
		return nil
	}
	opts := make([]modifierOption, 0, len(item.Modifiers))
	for _, m := range item.Modifiers {
		opts = append(opts, modifierOption{
			ID:         stableSlugID(m.Name),
			Name:       strings.TrimSpace(m.Name),
			PriceCents: m.PriceCents,
		})
	}
	return []modifierGroup{
		{
			ID:            "legacy_modifiers",
			Name:          "Options",
			Required:      false,
			MinSelections: 0,
			MaxSelections: len(opts),
			Options:       opts,
		},
	}
}

func stableSlugID(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return "id"
	}
	var b strings.Builder
	b.Grow(len(s))
	lastDash := false
	for _, r := range s {
		isAZ := r >= 'a' && r <= 'z'
		is09 := r >= '0' && r <= '9'
		if isAZ || is09 {
			b.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			b.WriteByte('-')
			lastDash = true
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		return "id"
	}
	return out
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

func handleWaitTimeSummary(
	parentCtx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	cache *storeWaitTimeMetaCache,
	w http.ResponseWriter,
	r *http.Request,
	storeID string,
) {
	ctx, cancel := context.WithTimeout(parentCtx, 2*time.Second)
	defer cancel()

	meta, err := getStoreWaitTimeMeta(ctx, fs, cache, storeID)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "store_meta_unavailable"})
		return
	}
	loc := meta.loc
	if loc == nil {
		loc = time.UTC
	}
	nowLocal := time.Now().In(loc)
	daypartKey := daypartFor(nowLocal)

	statsRef := fs.Collection(storesCollection).Doc(storeID).Collection(waitTimeStatsSubcollection).Doc(daypartKey)
	var stats waitTimeStatsDoc
	if doc, err := statsRef.Get(ctx); err == nil && doc.Exists() {
		_ = doc.DataTo(&stats)
	}

	defaultWait := meta.defaultWaitMinutes
	if defaultWait <= 0 {
		defaultWait = 15
	}

	samples := append([]int{}, stats.Samples...)
	sampleCount := len(samples)
	last := stats.LastDurationMinutes

	median := stats.MedianMinutes
	p90 := stats.P90Minutes
	if sampleCount > 0 {
		median = medianInt(samples)
		p90 = percentileInt(samples, 0.90)
	}

	method := "default"
	source := "store_default"
	eta := defaultWait
	if sampleCount > 0 {
		minSamples := cfg.WaitTimeMinSamples
		if minSamples <= 0 {
			minSamples = 10
		}
		if sampleCount < minSamples {
			method = "last"
			source = "historical_last"
			if last > 0 {
				eta = last
			} else {
				eta = samples[sampleCount-1]
			}
		} else {
			method = "median"
			source = "historical_median"
			if median > 0 {
				eta = median
			} else {
				eta = medianInt(samples)
			}
		}
	}

	eta = clampEta(defaultWait, eta)

	writeJSON(w, http.StatusOK, map[string]any{
		"storeId":             storeID,
		"daypartKeyUsed":      daypartKey,
		"etaMinutes":          eta,
		"source":              source,
		"method":              method,
		"medianMinutes":       median,
		"p90Minutes":          p90,
		"lastDurationMinutes": last,
		"count":               stats.Count,
		"sampleCount":         sampleCount,
		"defaultWaitMinutes":  defaultWait,
	})
}

type waitTimeAggFS struct {
	Count               int   `firestore:"count"`
	Samples             []int `firestore:"samples"`
	MedianMinutes       int   `firestore:"medianMinutes"`
	P90Minutes          int   `firestore:"p90Minutes"`
	LastDurationMinutes int   `firestore:"lastDurationMinutes"`
}

type waitTimeDailyDocFS struct {
	Date      string                   `firestore:"date"`
	UpdatedAt time.Time                `firestore:"updatedAt"`
	Overall   waitTimeAggFS            `firestore:"overall"`
	Dayparts  map[string]waitTimeAggFS `firestore:"dayparts"`
}

func handleWaitTimeDaily(
	parentCtx context.Context,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	cache *storeWaitTimeMetaCache,
	w http.ResponseWriter,
	r *http.Request,
	storeID string,
	days int,
) {
	ctx, cancel := context.WithTimeout(parentCtx, 3*time.Second)
	defer cancel()

	meta, err := getStoreWaitTimeMeta(ctx, fs, cache, storeID)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "store_meta_unavailable"})
		return
	}
	loc := meta.loc
	if loc == nil {
		loc = time.UTC
	}

	nowLocal := time.Now().In(loc)
	dateKeys := make([]string, 0, days)
	refs := make([]*cloudfirestore.DocumentRef, 0, days)
	for i := days - 1; i >= 0; i-- {
		key := nowLocal.AddDate(0, 0, -i).Format("2006-01-02")
		dateKeys = append(dateKeys, key)
		refs = append(refs, fs.Collection(storesCollection).Doc(storeID).Collection(waitTimeDailySubcollection).Doc(key))
	}

	snaps, err := fs.GetAll(ctx, refs)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "fetch_failed"})
		return
	}

	points := make([]waitTimeDailyPoint, 0, days)
	for i, snap := range snaps {
		key := dateKeys[i]
		if snap == nil || !snap.Exists() {
			points = append(points, waitTimeDailyPoint{
				Date:     key,
				Overall:  waitTimeAgg{},
				Dayparts: map[string]waitTimeAgg{},
			})
			continue
		}
		var doc waitTimeDailyDocFS
		_ = snap.DataTo(&doc)

		dayparts := map[string]waitTimeAgg{}
		for k, v := range doc.Dayparts {
			dayparts[k] = waitTimeAgg{
				Count:               v.Count,
				MedianMinutes:       v.MedianMinutes,
				P90Minutes:          v.P90Minutes,
				LastDurationMinutes: v.LastDurationMinutes,
			}
		}
		pt := waitTimeDailyPoint{
			Date: key,
			Overall: waitTimeAgg{
				Count:               doc.Overall.Count,
				MedianMinutes:       doc.Overall.MedianMinutes,
				P90Minutes:          doc.Overall.P90Minutes,
				LastDurationMinutes: doc.Overall.LastDurationMinutes,
			},
			Dayparts: dayparts,
		}
		if !doc.UpdatedAt.IsZero() {
			pt.UpdatedAt = doc.UpdatedAt.UTC().Format(time.RFC3339)
		}
		points = append(points, pt)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"storeId":            storeID,
		"days":               days,
		"defaultWaitMinutes": meta.defaultWaitMinutes,
		"points":             points,
	})
}

func getStoreWaitTimeMeta(ctx context.Context, fs *cloudfirestore.Client, cache *storeWaitTimeMetaCache, storeID string) (storeWaitTimeMeta, error) {
	if cache != nil {
		if m, ok := cache.get(storeID); ok {
			return m, nil
		}
	}

	doc, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil || !doc.Exists() {
		return storeWaitTimeMeta{}, fmt.Errorf("store_not_found")
	}
	var sd storeDoc
	_ = doc.DataTo(&sd)

	tenantID := strings.TrimSpace(firstNonEmpty(sd.TenantID, sd.TenantID2, anyToString(doc.Data()["tenant_id"]), anyToString(doc.Data()["tenantId"])))
	defaultWait := readDefaultWaitMinutes(sd.OrderComms)

	loc := time.UTC
	if tenantID != "" {
		tdoc, err := fs.Collection(tenantsCollection).Doc(tenantID).Get(ctx)
		if err == nil && tdoc.Exists() {
			var td tenantDoc
			_ = tdoc.DataTo(&td)
			if l := loadLocation(strings.TrimSpace(td.Timezone)); l != nil {
				loc = l
			}
		}
	}

	m := storeWaitTimeMeta{
		tenantID:           tenantID,
		defaultWaitMinutes: defaultWait,
		loc:                loc,
		fetchedAt:          time.Now(),
	}
	if cache != nil {
		cache.set(storeID, m)
	}
	return m, nil
}

func readDefaultWaitMinutes(orderComms map[string]any) int {
	if orderComms == nil {
		return 0
	}
	v, ok := orderComms["default_wait_minutes"]
	if !ok {
		return 0
	}
	switch t := v.(type) {
	case int:
		return t
	case int64:
		return int(t)
	case float64:
		return int(t)
	case string:
		n, _ := strconv.Atoi(strings.TrimSpace(t))
		return n
	default:
		return 0
	}
}

func daypartFor(t time.Time) string {
	weekend := t.Weekday() == time.Saturday || t.Weekday() == time.Sunday
	h := t.Hour()
	isLunch := h >= 11 && h < 16
	if weekend {
		if isLunch {
			return "weekend_lunch"
		}
		return "weekend_dinner"
	}
	if isLunch {
		return "weekday_lunch"
	}
	return "weekday_dinner"
}

func medianInt(samples []int) int {
	if len(samples) == 0 {
		return 0
	}
	s := append([]int{}, samples...)
	sort.Ints(s)
	mid := len(s) / 2
	if len(s)%2 == 1 {
		return s[mid]
	}
	return int(math.Round(float64(s[mid-1]+s[mid]) / 2.0))
}

func percentileInt(samples []int, p float64) int {
	if len(samples) == 0 {
		return 0
	}
	s := append([]int{}, samples...)
	sort.Ints(s)
	if p <= 0 {
		return s[0]
	}
	if p >= 1 {
		return s[len(s)-1]
	}
	rank := int(math.Ceil(p*float64(len(s)))) - 1
	if rank < 0 {
		rank = 0
	}
	if rank >= len(s) {
		rank = len(s) - 1
	}
	return s[rank]
}

func clampEta(defaultWait, eta int) int {
	eta = clampInt(eta, 3, 120)
	if defaultWait <= 0 {
		return eta
	}
	minBand := defaultWait / 2
	if minBand < 3 {
		minBand = 3
	}
	maxBand := defaultWait * 2
	if maxBand > 120 {
		maxBand = 120
	}
	if minBand > maxBand {
		return eta
	}
	return clampInt(eta, minBand, maxBand)
}

func clampInt(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func loadLocation(tz string) *time.Location {
	tz = strings.TrimSpace(tz)
	if tz == "" {
		return nil
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return nil
	}
	return loc
}

func anyToString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	default:
		return ""
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

const idempotencyCollection = "idempotency_keys"

var (
	ordersCreatedCounter uint64
	statusUpdateCounter  uint64
)
