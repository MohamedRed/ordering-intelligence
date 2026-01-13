package main

import (
  "bufio"
  "bytes"
  "context"
  "encoding/json"
  "fmt"
  "io"
  "log"
  "net/http"
  "os"
  "strings"
  "time"

  cloudfirestore "cloud.google.com/go/firestore"
  "google.golang.org/api/iterator"
  "google.golang.org/api/option"
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

func main() {
  cfg := loadTypesenseConfig()
  if cfg.Host == "" || cfg.APIKey == "" {
    log.Fatal("TYPESENSE_HOST and TYPESENSE_ADMIN_API_KEY must be set")
  }
  if cfg.Collection == "" {
    cfg.Collection = "stores"
  }

  ctx := context.Background()
  fs, err := newFirestoreClient(ctx)
  if err != nil {
    log.Fatalf("firestore init failed: %v", err)
  }
  defer fs.Close()

  if err := ensureTypesenseCollection(ctx, cfg); err != nil {
    log.Fatalf("typesense collection ensure failed: %v", err)
  }

  tenants, err := loadTenants(ctx, fs)
  if err != nil {
    log.Fatalf("load tenants failed: %v", err)
  }

  if err := syncStores(ctx, fs, cfg, tenants); err != nil {
    log.Fatalf("sync failed: %v", err)
  }
  log.Printf("typesense sync complete")
}

func loadTypesenseConfig() typesenseConfig {
  host := strings.TrimSpace(os.Getenv("TYPESENSE_HOST"))
  if host != "" && !strings.HasPrefix(host, "http://") && !strings.HasPrefix(host, "https://") {
    host = "https://" + host
  }
  return typesenseConfig{
    Host:       host,
    APIKey:     strings.TrimSpace(os.Getenv("TYPESENSE_ADMIN_API_KEY")),
    Collection: strings.TrimSpace(os.Getenv("TYPESENSE_COLLECTION")),
  }
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
  req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
  req.Header.Set("X-TYPESENSE-API-KEY", cfg.APIKey)
  req.Header.Set("Content-Type", "application/json")
  resp, err := http.DefaultClient.Do(req)
  if err != nil {
    return err
  }
  defer resp.Body.Close()
  if resp.StatusCode == 409 {
    return nil
  }
  if resp.StatusCode < 200 || resp.StatusCode >= 300 {
    data, _ := io.ReadAll(resp.Body)
    return fmt.Errorf("typesense collection create failed status=%d body=%s", resp.StatusCode, string(data))
  }
  return nil
}

func loadTenants(ctx context.Context, fs *cloudfirestore.Client) (map[string]string, error) {
  tenants := make(map[string]string)
  iter := fs.Collection(tenantsCollection).Documents(ctx)
  for {
    doc, err := iter.Next()
    if err != nil {
      if err == iterator.Done {
        break
      }
      return tenants, err
    }
    name := strings.TrimSpace(toString(doc.Data()["name"]))
    if name != "" {
      tenants[doc.Ref.ID] = name
    }
  }
  return tenants, nil
}

func syncStores(ctx context.Context, fs *cloudfirestore.Client, cfg typesenseConfig, tenants map[string]string) error {
  url := fmt.Sprintf("%s/collections/%s/documents/import?action=upsert", strings.TrimRight(cfg.Host, "/"), cfg.Collection)
  req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, nil)
  req.Header.Set("X-TYPESENSE-API-KEY", cfg.APIKey)
  req.Header.Set("Content-Type", "text/plain")

  pipeReader, pipeWriter := io.Pipe()
  req.Body = pipeReader

  done := make(chan error, 1)
  go func() {
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
      done <- err
      return
    }
    defer resp.Body.Close()
    if resp.StatusCode < 200 || resp.StatusCode >= 300 {
      data, _ := io.ReadAll(resp.Body)
      done <- fmt.Errorf("typesense import failed status=%d body=%s", resp.StatusCode, string(data))
      return
    }
    done <- nil
  }()

  writer := bufio.NewWriter(pipeWriter)
  iter := fs.Collection(storesCollection).Documents(ctx)
  for {
    doc, err := iter.Next()
    if err != nil {
      if err == iterator.Done {
        break
      }
      _ = pipeWriter.CloseWithError(err)
      return err
    }
    data := doc.Data()
    storeID := strings.TrimSpace(firstNonEmpty(toString(data["store_id"]), doc.Ref.ID))
    tenantID := strings.TrimSpace(firstNonEmpty(toString(data["tenant_id"]), toString(data["tenantId"])))
    if storeID == "" || tenantID == "" {
      continue
    }
    businessType := strings.TrimSpace(firstNonEmpty(toString(data["business_type"]), toString(data["businessType"])))
    storeName := strings.TrimSpace(firstNonEmpty(toString(data["name"]), toString(data["store_name"]), toString(data["display_name"])))
    tenantName := tenants[tenantID]
    name := storeName
    if name == "" {
      name = tenantName
    }
    if name == "" {
      name = storeID
    }

    docPayload := typesenseDoc{
      ID:           storeID,
      StoreID:      storeID,
      TenantID:     tenantID,
      BusinessType: businessType,
      Name:         name,
      TenantName:   tenantName,
      StoreName:    storeName,
    }
    line, _ := json.Marshal(docPayload)
    if _, err := writer.Write(line); err != nil {
      _ = pipeWriter.CloseWithError(err)
      return err
    }
    if _, err := writer.WriteString("\n"); err != nil {
      _ = pipeWriter.CloseWithError(err)
      return err
    }
  }

  _ = writer.Flush()
  _ = pipeWriter.Close()

  select {
  case err := <-done:
    return err
  case <-time.After(60 * time.Second):
    return fmt.Errorf("typesense import timed out")
  }
}

func toString(v any) string {
  if v == nil {
    return ""
  }
  switch t := v.(type) {
  case string:
    return t
  default:
    return fmt.Sprintf("%v", t)
  }
}

func firstNonEmpty(values ...string) string {
  for _, v := range values {
    if strings.TrimSpace(v) != "" {
      return v
    }
  }
  return ""
}
