package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	firestoredata "github.com/googleapis/google-cloudevents-go/cloud/firestoredata"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

const (
	storesCollection  = "stores"
	tenantsCollection = "tenants"
)

type typesenseConfig struct {
	Host       string
	APIKey     string
	Collection string
}

type typesenseCollectionSchema struct {
	Name   string               `json:"name"`
	Fields []typesenseFieldSpec `json:"fields"`
}

type typesenseFieldSpec struct {
	Name  string `json:"name"`
	Type  string `json:"type"`
	Facet bool   `json:"facet,omitempty"`
}

type typesenseDoc struct {
	ID           string `json:"id"`
	StoreID      string `json:"store_id"`
	TenantID     string `json:"tenant_id"`
	BusinessType string `json:"business_type,omitempty"`
	Name         string `json:"name"`
	TenantName   string `json:"tenant_name,omitempty"`
	StoreName    string `json:"store_name,omitempty"`
}

type cloudEvent struct {
	Type       string          `json:"type"`
	Subject    string          `json:"subject"`
	Data       json.RawMessage `json:"data"`
	DataBase64 string          `json:"data_base64"`
}

type firestoreEvent struct {
	Value    firestoreDoc `json:"value"`
	OldValue firestoreDoc `json:"oldValue"`
}

type firestoreDoc struct {
	Name   string                  `json:"name"`
	Fields map[string]firestoreVal `json:"fields"`
}

type firestoreVal struct {
	StringValue  *string              `json:"stringValue,omitempty"`
	IntegerValue *string              `json:"integerValue,omitempty"`
	DoubleValue  *float64             `json:"doubleValue,omitempty"`
	BooleanValue *bool                `json:"booleanValue,omitempty"`
	MapValue     *firestoreMapValue   `json:"mapValue,omitempty"`
	ArrayValue   *firestoreArrayValue `json:"arrayValue,omitempty"`
	NullValue    *string              `json:"nullValue,omitempty"`
	Timestamp    *string              `json:"timestampValue,omitempty"`
}

type firestoreMapValue struct {
	Fields map[string]firestoreVal `json:"fields"`
}

type firestoreArrayValue struct {
	Values []firestoreVal `json:"values"`
}

type service struct {
	firestore *cloudfirestore.Client
	cfg       typesenseConfig
	once      sync.Once
	ensureErr error
}

func main() {
	cfg := loadTypesenseConfig()
	ctx := context.Background()

	firestoreClient, err := newFirestoreClient(ctx)
	if err != nil {
		log.Fatalf("failed to create firestore client: %v", err)
	}
	defer firestoreClient.Close()

	srv := &service{firestore: firestoreClient, cfg: cfg}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/tasks/sync", srv.handleSync)
	mux.HandleFunc("/", srv.handleEvent)

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	log.Printf("typesense-indexer listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

func loadTypesenseConfig() typesenseConfig {
	host := strings.TrimSpace(os.Getenv("TYPESENSE_HOST"))
	if host != "" && !strings.HasPrefix(host, "http://") && !strings.HasPrefix(host, "https://") {
		host = "https://" + host
	}
	collection := strings.TrimSpace(os.Getenv("TYPESENSE_COLLECTION"))
	if collection == "" {
		collection = "stores"
	}
	return typesenseConfig{
		Host:       host,
		APIKey:     strings.TrimSpace(os.Getenv("TYPESENSE_ADMIN_API_KEY")),
		Collection: collection,
	}
}

func (s *service) handleEvent(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusBadRequest, "read_failed")
		return
	}

	if !s.cfg.enabled() {
		log.Printf("typesense-indexer disabled: missing TYPESENSE_HOST or TYPESENSE_ADMIN_API_KEY")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	if err := s.ensureCollection(ctx); err != nil {
		log.Printf("typesense collection ensure failed: %v", err)
		writeError(w, http.StatusInternalServerError, "typesense_collection_unavailable")
		return
	}

	event, err := decodeCloudEvent(body)
	if err != nil {
		log.Printf("cloud event decode failed: %v", err)
		writeError(w, http.StatusBadRequest, "invalid_event")
		return
	}

	fsEvent, err := decodeFirestoreEvent(event.Data)
	if err != nil {
		log.Printf("firestore event decode failed: %v", err)
		writeError(w, http.StatusBadRequest, "invalid_firestore_event")
		return
	}

	docName := firstNonEmpty(fsEvent.Value.Name, fsEvent.OldValue.Name, event.Subject)
	collection, docID := parseDocPath(docName)
	if collection == "" || docID == "" {
		log.Printf("missing firestore document path in event")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	isDelete := strings.Contains(event.Type, "deleted") || (fsEvent.Value.Name == "" && fsEvent.OldValue.Name != "")

	switch collection {
	case storesCollection:
		if isDelete {
			if err := s.deleteStore(ctx, docID); err != nil {
				log.Printf("typesense delete failed for store %s: %v", docID, err)
				writeError(w, http.StatusInternalServerError, "typesense_delete_failed")
				return
			}
			w.WriteHeader(http.StatusOK)
			return
		}
		if err := s.upsertStoreFromEvent(ctx, docID, fsEvent.Value.Fields); err != nil {
			log.Printf("typesense upsert failed for store %s: %v", docID, err)
			writeError(w, http.StatusInternalServerError, "typesense_upsert_failed")
			return
		}
		w.WriteHeader(http.StatusOK)
		return
	case tenantsCollection:
		if err := s.handleTenantEvent(ctx, docID, fsEvent.Value.Fields, isDelete); err != nil {
			log.Printf("tenant event failed for %s: %v", docID, err)
			writeError(w, http.StatusInternalServerError, "tenant_update_failed")
			return
		}
		w.WriteHeader(http.StatusOK)
		return
	default:
		w.WriteHeader(http.StatusNoContent)
		return
	}
}

func (s *service) handleSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	ctx := r.Context()
	if !s.cfg.enabled() {
		log.Printf("typesense-indexer disabled: missing TYPESENSE_HOST or TYPESENSE_ADMIN_API_KEY")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if err := s.ensureCollection(ctx); err != nil {
		log.Printf("typesense collection ensure failed: %v", err)
		writeError(w, http.StatusInternalServerError, "typesense_collection_unavailable")
		return
	}

	start := time.Now()
	stats, err := s.reconcileAllStores(ctx)
	if err != nil {
		log.Printf("typesense reconcile failed: %v", err)
		writeError(w, http.StatusInternalServerError, "typesense_reconcile_failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"indexed":        stats.indexed,
		"skipped":        stats.skipped,
		"duration_ms":    time.Since(start).Milliseconds(),
		"collection":     s.cfg.Collection,
		"stores_scanned": stats.scanned,
	})
}

func (s *service) ensureCollection(ctx context.Context) error {
	s.once.Do(func() {
		s.ensureErr = ensureTypesenseCollection(ctx, s.cfg)
	})
	return s.ensureErr
}

func (s *service) upsertStoreFromEvent(ctx context.Context, docID string, fields map[string]firestoreVal) error {
	storeID := strings.TrimSpace(firstNonEmpty(fieldString(fields, "store_id", "storeId"), docID))
	if storeID == "" {
		return nil
	}

	storeFields := fields
	if len(storeFields) == 0 {
		snap, err := s.firestore.Collection(storesCollection).Doc(storeID).Get(ctx)
		if err != nil {
			return err
		}
		return s.upsertStoreFromMap(ctx, storeID, snap.Data(), "")
	}

	tenantID := strings.TrimSpace(fieldString(storeFields, "tenant_id", "tenantId"))
	tenantName := ""
	if tenantID != "" {
		name, err := s.fetchTenantName(ctx, tenantID)
		if err != nil {
			log.Printf("fetch tenant name failed for %s: %v", tenantID, err)
		} else {
			tenantName = name
		}
	}

	doc := buildTypesenseDoc(storeID, tenantID, tenantName, storeFields)
	if doc.ID == "" || doc.TenantID == "" {
		return nil
	}
	return upsertTypesenseDoc(ctx, s.cfg, doc)
}

func (s *service) upsertStoreFromMap(ctx context.Context, storeID string, data map[string]any, tenantName string) error {
	tenantID := strings.TrimSpace(firstNonEmpty(toString(data["tenant_id"]), toString(data["tenantId"])))
	if tenantID == "" {
		return nil
	}
	if tenantName == "" {
		name, err := s.fetchTenantName(ctx, tenantID)
		if err == nil {
			tenantName = name
		}
	}

	doc := buildTypesenseDocFromMap(storeID, tenantID, tenantName, data)
	if doc.ID == "" || doc.TenantID == "" {
		return nil
	}
	return upsertTypesenseDoc(ctx, s.cfg, doc)
}

func (s *service) handleTenantEvent(ctx context.Context, tenantID string, fields map[string]firestoreVal, isDelete bool) error {
	tenantName := ""
	if !isDelete {
		tenantName = strings.TrimSpace(fieldString(fields, "name", "display_name", "displayName"))
	}
	if tenantName == "" {
		name, err := s.fetchTenantName(ctx, tenantID)
		if err == nil {
			tenantName = name
		}
	}

	stores, err := s.fetchStoresForTenant(ctx, tenantID)
	if err != nil {
		return err
	}
	for _, store := range stores {
		if err := s.upsertStoreFromMap(ctx, store.id, store.data, tenantName); err != nil {
			return err
		}
	}
	return nil
}

func (s *service) fetchStoresForTenant(ctx context.Context, tenantID string) ([]storeDoc, error) {
	seen := make(map[string]struct{})
	stores := []storeDoc{}

	for _, field := range []string{"tenant_id", "tenantId"} {
		iter := s.firestore.Collection(storesCollection).Where(field, "==", tenantID).Documents(ctx)
		for {
			doc, err := iter.Next()
			if err != nil {
				if err == iterator.Done {
					break
				}
				return stores, err
			}
			storeID := strings.TrimSpace(firstNonEmpty(toString(doc.Data()["store_id"]), toString(doc.Data()["storeId"]), doc.Ref.ID))
			if storeID == "" {
				continue
			}
			if _, exists := seen[storeID]; exists {
				continue
			}
			seen[storeID] = struct{}{}
			stores = append(stores, storeDoc{id: storeID, data: doc.Data()})
		}
	}
	return stores, nil
}

func (s *service) fetchTenantName(ctx context.Context, tenantID string) (string, error) {
	snap, err := s.firestore.Collection(tenantsCollection).Doc(tenantID).Get(ctx)
	if err != nil {
		return "", err
	}
	data := snap.Data()
	return strings.TrimSpace(firstNonEmpty(toString(data["name"]), toString(data["display_name"]), toString(data["displayName"]))), nil
}

type reconcileStats struct {
	scanned int
	indexed int
	skipped int
}

func (s *service) reconcileAllStores(ctx context.Context) (reconcileStats, error) {
	stats := reconcileStats{}
	iter := s.firestore.Collection(storesCollection).Documents(ctx)
	for {
		doc, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				break
			}
			return stats, err
		}
		stats.scanned++
		storeID := strings.TrimSpace(firstNonEmpty(toString(doc.Data()["store_id"]), toString(doc.Data()["storeId"]), doc.Ref.ID))
		if storeID == "" {
			stats.skipped++
			continue
		}
		if err := s.upsertStoreFromMap(ctx, storeID, doc.Data(), ""); err != nil {
			return stats, err
		}
		stats.indexed++
	}
	return stats, nil
}

func (s *service) deleteStore(ctx context.Context, storeID string) error {
	if storeID == "" {
		return nil
	}
	return deleteTypesenseDoc(ctx, s.cfg, storeID)
}

func decodeCloudEvent(body []byte) (cloudEvent, error) {
	var evt cloudEvent
	if err := json.Unmarshal(body, &evt); err != nil {
		return evt, err
	}
	if len(evt.Data) == 0 && evt.DataBase64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(evt.DataBase64)
		if err != nil {
			return evt, err
		}
		evt.Data = decoded
	}
	return evt, nil
}

func decodeFirestoreEvent(data []byte) (firestoreEvent, error) {
	var evt firestoreEvent
	if len(data) == 0 {
		return evt, fmt.Errorf("missing event data")
	}
	if err := json.Unmarshal(data, &evt); err == nil {
		return evt, nil
	}

	var protoEvt firestoredata.DocumentEventData
	if err := proto.Unmarshal(data, &protoEvt); err != nil {
		return evt, err
	}

	decoded, err := protojson.Marshal(&protoEvt)
	if err != nil {
		return evt, err
	}
	if err := json.Unmarshal(decoded, &evt); err != nil {
		return evt, err
	}
	return evt, nil
}

func (cfg typesenseConfig) enabled() bool {
	return strings.TrimSpace(cfg.Host) != "" && strings.TrimSpace(cfg.APIKey) != ""
}

func ensureTypesenseCollection(ctx context.Context, cfg typesenseConfig) error {
	schema := typesenseCollectionSchema{
		Name: cfg.Collection,
		Fields: []typesenseFieldSpec{
			{Name: "name", Type: "string"},
			{Name: "tenant_name", Type: "string"},
			{Name: "store_name", Type: "string"},
			{Name: "store_id", Type: "string", Facet: true},
			{Name: "tenant_id", Type: "string", Facet: true},
			{Name: "business_type", Type: "string", Facet: true},
		},
	}
	body, _ := json.Marshal(schema)
	url := fmt.Sprintf("%s/collections", strings.TrimRight(cfg.Host, "/"))
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(body)))
	req.Header.Set("X-TYPESENSE-API-KEY", cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusConflict {
		return nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("typesense collection create failed status=%d body=%s", resp.StatusCode, string(data))
	}
	return nil
}

func upsertTypesenseDoc(ctx context.Context, cfg typesenseConfig, doc typesenseDoc) error {
	url := fmt.Sprintf("%s/collections/%s/documents?action=upsert", strings.TrimRight(cfg.Host, "/"), cfg.Collection)
	body, _ := json.Marshal(doc)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(body)))
	req.Header.Set("X-TYPESENSE-API-KEY", cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("typesense upsert failed status=%d body=%s", resp.StatusCode, string(data))
	}
	return nil
}

func deleteTypesenseDoc(ctx context.Context, cfg typesenseConfig, docID string) error {
	url := fmt.Sprintf("%s/collections/%s/documents/%s", strings.TrimRight(cfg.Host, "/"), cfg.Collection, docID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodDelete, url, nil)
	req.Header.Set("X-TYPESENSE-API-KEY", cfg.APIKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("typesense delete failed status=%d body=%s", resp.StatusCode, string(data))
	}
	return nil
}

func newFirestoreClient(ctx context.Context) (*cloudfirestore.Client, error) {
	projectID := strings.TrimSpace(os.Getenv("FIRESTORE_PROJECT_ID"))
	if projectID == "" {
		projectID = strings.TrimSpace(os.Getenv("GOOGLE_CLOUD_PROJECT"))
	}
	if projectID == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not set")
	}
	creds := strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"))
	opts := []option.ClientOption{}
	if creds != "" {
		opts = append(opts, option.WithCredentialsFile(creds))
	}
	return cloudfirestore.NewClient(ctx, projectID, opts...)
}

func parseDocPath(name string) (string, string) {
	if name == "" {
		return "", ""
	}
	if idx := strings.Index(name, "/documents/"); idx >= 0 {
		name = name[idx+len("/documents/"):]
	}
	parts := strings.Split(name, "/")
	if len(parts) < 2 {
		return "", ""
	}
	return parts[0], parts[1]
}

func fieldString(fields map[string]firestoreVal, keys ...string) string {
	for _, key := range keys {
		if fields == nil {
			return ""
		}
		if val, ok := fields[key]; ok {
			if s := val.String(); strings.TrimSpace(s) != "" {
				return s
			}
		}
	}
	return ""
}

func (v firestoreVal) String() string {
	switch {
	case v.StringValue != nil:
		return *v.StringValue
	case v.IntegerValue != nil:
		return *v.IntegerValue
	case v.DoubleValue != nil:
		return fmt.Sprintf("%v", *v.DoubleValue)
	case v.BooleanValue != nil:
		if *v.BooleanValue {
			return "true"
		}
		return "false"
	case v.Timestamp != nil:
		return *v.Timestamp
	default:
		return ""
	}
}

func buildTypesenseDoc(storeID, tenantID, tenantName string, fields map[string]firestoreVal) typesenseDoc {
	businessType := strings.TrimSpace(fieldString(fields, "business_type", "businessType"))
	storeName := strings.TrimSpace(fieldString(fields, "name", "store_name", "display_name", "displayName"))
	name := storeName
	if name == "" {
		name = tenantName
	}
	if name == "" {
		name = storeID
	}
	return typesenseDoc{
		ID:           storeID,
		StoreID:      storeID,
		TenantID:     tenantID,
		BusinessType: businessType,
		Name:         name,
		TenantName:   tenantName,
		StoreName:    storeName,
	}
}

func buildTypesenseDocFromMap(storeID, tenantID, tenantName string, data map[string]any) typesenseDoc {
	businessType := strings.TrimSpace(firstNonEmpty(toString(data["business_type"]), toString(data["businessType"])))
	storeName := strings.TrimSpace(firstNonEmpty(toString(data["name"]), toString(data["store_name"]), toString(data["display_name"]), toString(data["displayName"])))
	name := storeName
	if name == "" {
		name = tenantName
	}
	if name == "" {
		name = storeID
	}
	return typesenseDoc{
		ID:           storeID,
		StoreID:      storeID,
		TenantID:     tenantID,
		BusinessType: businessType,
		Name:         name,
		TenantName:   tenantName,
		StoreName:    storeName,
	}
}

type storeDoc struct {
	id   string
	data map[string]any
}

func toString(v any) string {
	if v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case fmt.Stringer:
		return t.String()
	default:
		return fmt.Sprintf("%v", t)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func writeError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"error": code,
		"time":  time.Now().UTC().Format(time.RFC3339),
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
