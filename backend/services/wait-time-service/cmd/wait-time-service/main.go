package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/joho/godotenv"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	storesCollection              = "stores"
	tenantsCollection             = "tenants"
	waitTimeStatsSubcollection    = "wait_time_stats"
	waitTimeDailySubcollection    = "wait_time_daily"
	waitTimeIngestDedupCollection = "wait_time_ingest_dedup"

	defaultPort              = "8080"
	defaultMinSamplesMedian  = 10
	defaultMaxSamplesHistory = 50
)

type serviceConfig struct {
	Port               string
	Environment        string
	FirestoreProjectID string
	CredentialsFile    string
	MinSamplesMedian   int
	MaxSamplesHistory  int
}

type pubsubPushEnvelope struct {
	Message struct {
		Data      string            `json:"data"`
		MessageID string            `json:"messageId"`
		Attrs     map[string]string `json:"attributes"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type orderRecord struct {
	ID        string     `json:"id"`
	StoreID   string     `json:"storeId"`
	TenantID  string     `json:"tenantId"`
	Status    string     `json:"status"`
	CreatedAt time.Time  `json:"createdAt"`
	ReadyAt   *time.Time `json:"readyAt,omitempty"`
}

type orderEventEnvelope struct {
	Kind      string       `json:"kind"`
	Order     *orderRecord `json:"order,omitempty"`
	CreatedAt string       `json:"createdAt,omitempty"`
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
	Count               int   `firestore:"count"`
	Samples             []int `firestore:"samples"`
	MedianMinutes       int   `firestore:"medianMinutes"`
	P90Minutes          int   `firestore:"p90Minutes"`
	LastDurationMinutes int   `firestore:"lastDurationMinutes"`
}

type waitTimeDailyDoc struct {
	Date      string                 `firestore:"date"`
	UpdatedAt time.Time              `firestore:"updatedAt"`
	Overall   waitTimeAgg            `firestore:"overall"`
	Dayparts  map[string]waitTimeAgg `firestore:"dayparts"`
}

type storeMeta struct {
	tenantID           string
	defaultWaitMinutes int
	loc                *time.Location
	fetchedAt          time.Time
}

type storeMetaCache struct {
	mu   sync.Mutex
	byID map[string]storeMeta
}

func newStoreMetaCache() *storeMetaCache {
	return &storeMetaCache{byID: make(map[string]storeMeta)}
}

func (c *storeMetaCache) get(storeID string) (storeMeta, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	m, ok := c.byID[storeID]
	if !ok {
		return storeMeta{}, false
	}
	// 5 minute TTL.
	if time.Since(m.fetchedAt) > 5*time.Minute {
		return storeMeta{}, false
	}
	return m, true
}

func (c *storeMetaCache) set(storeID string, m storeMeta) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.byID[storeID] = m
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

	metaCache := newStoreMetaCache()

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "ok",
			"service":     "wait-time-service",
			"environment": cfg.Environment,
		})
	})

	// Pub/Sub push endpoint for orders-events.
	r.Post("/tasks/orders-events", func(w http.ResponseWriter, r *http.Request) {
		handleOrdersEvents(w, r, fs, cfg, metaCache)
	})

	// Internal estimate endpoint (invocation protected by Cloud Run IAM in Terraform).
	r.Get("/v1/stores/{storeID}/wait-time/estimate", func(w http.ResponseWriter, r *http.Request) {
		storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
		if storeID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
			return
		}
		handleEstimate(w, r, fs, cfg, metaCache, storeID)
	})

	log.Printf("wait-time-service listening on :%s", cfg.Port)
	log.Fatal(http.ListenAndServe(":"+cfg.Port, r))
}

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("wait-time-service", nil)
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

	minSamples := intFromEnv("MIN_SAMPLES_FOR_MEDIAN", defaultMinSamplesMedian)
	maxSamples := intFromEnv("MAX_SAMPLES_HISTORY", defaultMaxSamplesHistory)
	if minSamples < 1 {
		minSamples = defaultMinSamplesMedian
	}
	if maxSamples < 10 {
		maxSamples = defaultMaxSamplesHistory
	}

	return &serviceConfig{
		Port:               port,
		Environment:        strings.TrimSpace(stringOrDefault(values["ENVIRONMENT"], "development")),
		FirestoreProjectID: project,
		CredentialsFile:    strings.TrimSpace(stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], "")),
		MinSamplesMedian:   minSamples,
		MaxSamplesHistory:  maxSamples,
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	var opts []option.ClientOption
	if strings.TrimSpace(cfg.CredentialsFile) != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.CredentialsFile))
	}
	return cloudfirestore.NewClient(ctx, cfg.FirestoreProjectID, opts...)
}

func handleOrdersEvents(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	cache *storeMetaCache,
) {
	raw, messageID, reason, err := decodePubSubPushData(r.Body)
	if err != nil {
		log.Printf("skipping malformed wait time orders Pub/Sub event reason=%s err=%v", reason, err)
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_invalid_pubsub", "reason": reason})
		return
	}

	// Support both legacy raw order payloads and v2 envelopes (e.g. order_customer_comms).
	var order orderRecord
	var env2 orderEventEnvelope
	if err := json.Unmarshal(raw, &env2); err == nil && strings.TrimSpace(env2.Kind) != "" {
		kind := strings.TrimSpace(env2.Kind)
		if kind == "order_customer_comms" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_customer_comms"})
			return
		}
		if env2.Order == nil {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_unknown_envelope"})
			return
		}
		order = *env2.Order
	} else {
		if err := json.Unmarshal(raw, &order); err != nil {
			log.Printf("skipping malformed wait time order event payload reason=%s err=%v", pubsubDecodeInvalidPayload, err)
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_invalid_pubsub", "reason": pubsubDecodeInvalidPayload})
			return
		}
	}

	storeID := strings.TrimSpace(order.StoreID)
	orderID := strings.TrimSpace(order.ID)
	if storeID == "" || orderID == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_ids"})
		return
	}

	if strings.ToLower(strings.TrimSpace(order.Status)) != "ready" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_not_ready"})
		return
	}
	if order.ReadyAt == nil || order.CreatedAt.IsZero() {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_timestamps"})
		return
	}

	durationMinutes := int(math.Round(order.ReadyAt.Sub(order.CreatedAt).Minutes()))
	if durationMinutes <= 0 {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_non_positive_duration"})
		return
	}
	// Store a bounded, sane sample value.
	durationMinutes = clampInt(durationMinutes, 1, 240)

	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()

	meta, err := getStoreMeta(ctx, fs, cache, storeID)
	if err != nil {
		log.Printf("orders-events: store meta fetch failed store=%s err=%v", storeID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_meta_fetch_failed"})
		return
	}
	loc := meta.loc
	if loc == nil {
		loc = time.UTC
	}

	daypartKey := daypartFor(order.CreatedAt.In(loc))
	dateKey := order.CreatedAt.In(loc).Format("2006-01-02")

	err = fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		dedupID := storeID + "__" + orderID
		dedupRef := fs.Collection(waitTimeIngestDedupCollection).Doc(dedupID)
		if snap, err := tx.Get(dedupRef); err == nil && snap.Exists() {
			return nil
		} else if err != nil && status.Code(err) != codes.NotFound {
			return err
		}

		statsRef := fs.Collection(storesCollection).Doc(storeID).Collection(waitTimeStatsSubcollection).Doc(daypartKey)
		var existing waitTimeStatsDoc
		if snap, err := tx.Get(statsRef); err == nil && snap.Exists() {
			_ = snap.DataTo(&existing)
		} else if err != nil && status.Code(err) != codes.NotFound {
			return err
		}

		// Daily aggregates for a 7-day UI (we keep per-day docs keyed by local date).
		// NOTE: Firestore transactions cannot read after any write; ensure all reads happen first.
		dailyRef := fs.Collection(storesCollection).Doc(storeID).Collection(waitTimeDailySubcollection).Doc(dateKey)
		var daily waitTimeDailyDoc
		if snap, err := tx.Get(dailyRef); err == nil && snap.Exists() {
			_ = snap.DataTo(&daily)
		} else if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if daily.Dayparts == nil {
			daily.Dayparts = make(map[string]waitTimeAgg)
		}

		samples := append([]int{}, existing.Samples...)
		samples = append(samples, durationMinutes)
		if max := cfg.MaxSamplesHistory; max > 0 && len(samples) > max {
			samples = samples[len(samples)-max:]
		}

		nextCount := existing.Count + 1
		median := medianInt(samples)
		p90 := percentileInt(samples, 0.90)
		now := time.Now().UTC()

		dpAgg := daily.Dayparts[daypartKey]
		dpSamples := append([]int{}, dpAgg.Samples...)
		dpSamples = append(dpSamples, durationMinutes)
		if max := cfg.MaxSamplesHistory; max > 0 && len(dpSamples) > max {
			dpSamples = dpSamples[len(dpSamples)-max:]
		}
		dpAgg.Count++
		dpAgg.Samples = dpSamples
		dpAgg.LastDurationMinutes = durationMinutes
		dpAgg.MedianMinutes = medianInt(dpSamples)
		dpAgg.P90Minutes = percentileInt(dpSamples, 0.90)
		daily.Dayparts[daypartKey] = dpAgg

		overallAgg := daily.Overall
		overallSamples := append([]int{}, overallAgg.Samples...)
		overallSamples = append(overallSamples, durationMinutes)
		if max := cfg.MaxSamplesHistory; max > 0 && len(overallSamples) > max {
			overallSamples = overallSamples[len(overallSamples)-max:]
		}
		overallAgg.Count++
		overallAgg.Samples = overallSamples
		overallAgg.LastDurationMinutes = durationMinutes
		overallAgg.MedianMinutes = medianInt(overallSamples)
		overallAgg.P90Minutes = percentileInt(overallSamples, 0.90)

		daypartsOut := make(map[string]any, len(daily.Dayparts))
		for k, v := range daily.Dayparts {
			daypartsOut[k] = map[string]any{
				"count":               v.Count,
				"samples":             v.Samples,
				"medianMinutes":       v.MedianMinutes,
				"p90Minutes":          v.P90Minutes,
				"lastDurationMinutes": v.LastDurationMinutes,
			}
		}

		if err := tx.Set(dedupRef, map[string]any{
			"storeId":         storeID,
			"orderId":         orderID,
			"daypartKey":      daypartKey,
			"durationMinutes": durationMinutes,
			"createdAt":       order.CreatedAt,
			"readyAt":         *order.ReadyAt,
			"ingestedAt":      now,
			"pubsubMessageId": messageID,
		}, cloudfirestore.MergeAll); err != nil {
			return err
		}

		if err := tx.Set(statsRef, map[string]any{
			"daypartKey":          daypartKey,
			"count":               nextCount,
			"samples":             samples,
			"medianMinutes":       median,
			"p90Minutes":          p90,
			"lastDurationMinutes": durationMinutes,
			"updatedAt":           now,
		}, cloudfirestore.MergeAll); err != nil {
			return err
		}

		return tx.Set(dailyRef, map[string]any{
			"date":      dateKey,
			"updatedAt": now,
			"overall": map[string]any{
				"count":               overallAgg.Count,
				"samples":             overallAgg.Samples,
				"medianMinutes":       overallAgg.MedianMinutes,
				"p90Minutes":          overallAgg.P90Minutes,
				"lastDurationMinutes": overallAgg.LastDurationMinutes,
			},
			"dayparts": daypartsOut,
		}, cloudfirestore.MergeAll)
	})
	if err != nil {
		log.Printf("orders-events: stats update failed store=%s order=%s err=%v", storeID, orderID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "stats_update_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":          "ok",
		"storeId":         storeID,
		"orderId":         orderID,
		"daypartKey":      daypartKey,
		"durationMinutes": durationMinutes,
	})
}

func handleEstimate(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	cache *storeMetaCache,
	storeID string,
) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	meta, err := getStoreMeta(ctx, fs, cache, storeID)
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
	last := stats.LastDurationMinutes
	median := stats.MedianMinutes
	p90 := stats.P90Minutes
	method := "default"
	eta := defaultWait
	if len(samples) > 0 {
		if len(samples) < cfg.MinSamplesMedian {
			method = "last"
			if last > 0 {
				eta = last
			} else {
				eta = samples[len(samples)-1]
			}
		} else {
			method = "median"
			eta = medianInt(samples)
		}
		median = medianInt(samples)
		p90 = percentileInt(samples, 0.90)
	}

	eta = clampEta(defaultWait, eta)

	writeJSON(w, http.StatusOK, map[string]any{
		"storeId":             storeID,
		"daypartKey":          daypartKey,
		"etaMinutes":          eta,
		"method":              method,
		"defaultWaitMinutes":  defaultWait,
		"sampleCount":         len(samples),
		"medianMinutes":       median,
		"p90Minutes":          p90,
		"lastDurationMinutes": last,
	})
}

func getStoreMeta(ctx context.Context, fs *cloudfirestore.Client, cache *storeMetaCache, storeID string) (storeMeta, error) {
	if cache != nil {
		if m, ok := cache.get(storeID); ok {
			return m, nil
		}
	}

	doc, err := fs.Collection(storesCollection).Doc(storeID).Get(ctx)
	if err != nil || !doc.Exists() {
		return storeMeta{}, fmt.Errorf("store_not_found")
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

	m := storeMeta{
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
	// Nearest-rank: ceil(p*n) (1-indexed), then convert to 0-index.
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

func intFromEnv(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return n
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

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
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
