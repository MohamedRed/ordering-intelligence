package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
)

const reordersCollection = "customer_reorders"

type serviceConfig struct {
	Port             string
	Environment      string
	FirestoreProject string
	CredentialsFile  string
}

type pubsubPushEnvelope struct {
	Message struct {
		Data string `json:"data"`
		ID   string `json:"messageId"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type orderItem struct {
	ItemID    string `json:"itemId"`
	Name      string `json:"name"`
	Quantity  int    `json:"quantity"`
	Category  string `json:"category"`
	Modifiers []struct {
		Name       string `json:"name"`
		PriceCents int64  `json:"priceCents"`
	} `json:"modifiers"`
}

type orderEvent struct {
	ID           string      `json:"id"`
	StoreID      string      `json:"storeId"`
	CreatedAt    time.Time   `json:"createdAt"`
	TenantID     string      `json:"tenantId,omitempty"`
	CustomerID   string      `json:"customerId"`
	BusinessType string      `json:"businessType,omitempty"`
	Items        []orderItem `json:"items"`
	Fuel         *fuelOrder  `json:"fuel,omitempty"`
}

type fuelOrder struct {
	FuelGradeID          string  `json:"fuelGradeId"`
	FuelGradeName        string  `json:"fuelGradeName,omitempty"`
	Unit                 string  `json:"unit,omitempty"`
	UnitPriceCents       int64   `json:"unitPriceCents,omitempty"`
	RequestedLiters      float64 `json:"requestedLiters,omitempty"`
	RequestedAmountCents int64   `json:"requestedAmountCents,omitempty"`
	PreauthAmountCents   int64   `json:"preauthAmountCents,omitempty"`
	PaymentFlow          string  `json:"paymentFlow,omitempty"`
}

type reorderTemplate struct {
	OrderTemplateID string      `json:"orderTemplateId" firestore:"orderTemplateId"`
	Title           string      `json:"title" firestore:"title"`
	Items           []orderItem `json:"items" firestore:"items"`
	Fuel            *fuelOrder  `json:"fuel,omitempty" firestore:"fuel,omitempty"`
	LastOrderedAt   time.Time   `json:"lastOrderedAt" firestore:"lastOrderedAt"`
}

type reorderDoc struct {
	StoreID     string            `json:"storeId" firestore:"storeId"`
	CustomerID  string            `json:"customerId" firestore:"customerId"`
	TopReorders []reorderTemplate `json:"topReorders" firestore:"topReorders"`
	UpdatedAt   time.Time         `json:"updatedAt" firestore:"updatedAt"`
}

func main() {
	_ = godotenv.Load()
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	ctx := context.Background()
	fs, err := newFirestoreClient(ctx, cfg)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer fs.Close()

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "ok",
			"service":     "recommendation-service",
			"environment": cfg.Environment,
		})
	})

	// GET /v1/reorders/top?tenantId=...&customerId=...&storeId=...
	r.Get("/v1/reorders/top", func(w http.ResponseWriter, r *http.Request) {
		customerID := strings.TrimSpace(r.URL.Query().Get("customerId"))
		storeID := strings.TrimSpace(r.URL.Query().Get("storeId"))
		if customerID == "" || storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_params"})
			return
		}
		docID := reordersDocID(customerID, storeID)
		ctx, cancel := context.WithTimeout(r.Context(), 800*time.Millisecond)
		defer cancel()
		doc, err := fs.Collection(reordersCollection).Doc(docID).Get(ctx)
		if err != nil || !doc.Exists() {
			writeJSON(w, http.StatusOK, map[string]any{"topReorders": []any{}})
			return
		}
		var rd reorderDoc
		_ = doc.DataTo(&rd)
		writeJSON(w, http.StatusOK, map[string]any{"topReorders": rd.TopReorders})
	})

	// Pub/Sub push endpoint for orders-events.
	r.Post("/tasks/orders-events", func(w http.ResponseWriter, r *http.Request) {
		var env pubsubPushEnvelope
		if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_pubsub_envelope"})
			return
		}
		raw, err := base64.StdEncoding.DecodeString(env.Message.Data)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_base64"})
			return
		}
		var evt orderEvent
		if err := json.Unmarshal(raw, &evt); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_event_json"})
			return
		}
		evt.CustomerID = strings.TrimSpace(evt.CustomerID)
		evt.StoreID = strings.TrimSpace(evt.StoreID)
		if evt.CustomerID == "" || evt.StoreID == "" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_identity"})
			return
		}
		hasFuel := evt.Fuel != nil && strings.EqualFold(strings.TrimSpace(evt.BusinessType), "gas_station")
		if len(evt.Items) == 0 && !hasFuel {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_no_items"})
			return
		}

		var templateID string
		var title string
		var items []orderItem
		var fuel *fuelOrder
		if len(evt.Items) > 0 {
			templateID = orderTemplateID(evt.Items)
			title = templateTitle(evt.Items)
			items = evt.Items
		} else if hasFuel {
			templateID = fuelTemplateID(*evt.Fuel)
			title = fuelTemplateTitle(*evt.Fuel)
			fuel = evt.Fuel
		}

		docID := reordersDocID(evt.CustomerID, evt.StoreID)
		now := time.Now().UTC()
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		err = fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
			ref := fs.Collection(reordersCollection).Doc(docID)
			snap, err := tx.Get(ref)
			var existing reorderDoc
			if err == nil && snap.Exists() {
				_ = snap.DataTo(&existing)
			}

			// Update last-3-distinct list.
			next := upsertLastDistinct(existing.TopReorders, reorderTemplate{
				OrderTemplateID: templateID,
				Title:           title,
				Items:           items,
				Fuel:            fuel,
				LastOrderedAt:   evt.CreatedAt,
			})

			payload := map[string]any{
				"storeId":     evt.StoreID,
				"customerId":  evt.CustomerID,
				"topReorders": next,
				"updatedAt":   now,
			}
			return tx.Set(ref, payload, cloudfirestore.MergeAll)
		})
		if err != nil {
			log.Printf("failed updating reorders doc=%s err=%v", docID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	log.Printf("recommendation-service listening on :%s", cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, r))
}

func upsertLastDistinct(existing []reorderTemplate, newest reorderTemplate) []reorderTemplate {
	// If head matches, just update timestamp/items/title.
	if len(existing) > 0 && existing[0].OrderTemplateID == newest.OrderTemplateID {
		existing[0] = newest
		return trim3(existing)
	}
	// Remove any existing occurrence.
	out := make([]reorderTemplate, 0, 3)
	out = append(out, newest)
	for _, t := range existing {
		if t.OrderTemplateID == newest.OrderTemplateID {
			continue
		}
		out = append(out, t)
	}
	return trim3(out)
}

func trim3(in []reorderTemplate) []reorderTemplate {
	if len(in) <= 3 {
		return in
	}
	return in[:3]
}

func orderTemplateID(items []orderItem) string {
	// Stable hash based on itemId, qty, and modifiers (sorted).
	type normMod struct{ Name string }
	type normItem struct {
		ID   string
		Qty  int
		Mods []normMod
	}
	n := make([]normItem, 0, len(items))
	for _, it := range items {
		ni := normItem{ID: strings.TrimSpace(it.ItemID), Qty: it.Quantity}
		for _, m := range it.Modifiers {
			name := strings.TrimSpace(m.Name)
			if name != "" {
				ni.Mods = append(ni.Mods, normMod{Name: name})
			}
		}
		sort.Slice(ni.Mods, func(i, j int) bool { return ni.Mods[i].Name < ni.Mods[j].Name })
		n = append(n, ni)
	}
	sort.Slice(n, func(i, j int) bool {
		if n[i].ID != n[j].ID {
			return n[i].ID < n[j].ID
		}
		return n[i].Qty < n[j].Qty
	})
	raw, _ := json.Marshal(n)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

func fuelTemplateID(fuel fuelOrder) string {
	payload := map[string]any{
		"gradeId":     strings.TrimSpace(fuel.FuelGradeID),
		"gradeName":   strings.TrimSpace(fuel.FuelGradeName),
		"unit":        strings.TrimSpace(fuel.Unit),
		"unitPrice":   fuel.UnitPriceCents,
		"requestedL":  fuel.RequestedLiters,
		"requestedC":  fuel.RequestedAmountCents,
		"preauthC":    fuel.PreauthAmountCents,
		"paymentFlow": strings.ToLower(strings.TrimSpace(fuel.PaymentFlow)),
	}
	raw, _ := json.Marshal(payload)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

func templateTitle(items []orderItem) string {
	// Simple deterministic title: first item name + count.
	first := strings.TrimSpace(items[0].Name)
	if first == "" {
		first = "Commande habituelle"
	}
	if len(items) == 1 {
		return first
	}
	return fmt.Sprintf("%s + %d article(s)", first, len(items)-1)
}

func fuelTemplateTitle(fuel fuelOrder) string {
	grade := strings.TrimSpace(fuel.FuelGradeName)
	if grade == "" {
		grade = strings.TrimSpace(fuel.FuelGradeID)
	}
	if grade == "" {
		grade = "Fuel order"
	}
	flow := strings.ToLower(strings.TrimSpace(fuel.PaymentFlow))
	if flow == "preauth" {
		return fmt.Sprintf("%s (preauth)", grade)
	}
	return grade
}

func reordersDocID(customerID, storeID string) string {
	return fmt.Sprintf("%s_%s", strings.TrimSpace(customerID), strings.TrimSpace(storeID))
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("recommendation-service", nil)
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

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func stringOrDefault(value interface{}, fallback string) string {
	switch v := value.(type) {
	case string:
		if strings.TrimSpace(v) == "" {
			return fallback
		}
		return v
	default:
		return fallback
	}
}
