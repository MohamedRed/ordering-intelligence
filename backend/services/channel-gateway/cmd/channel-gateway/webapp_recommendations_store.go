package main

import (
	"context"
	"net/http"
	"sort"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleWebAppStoreReorders(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	storeID := strings.TrimSpace(r.URL.Query().Get("storeId"))
	limit := limitFromQuery(r, 3)
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, client, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if storeID == "" {
		storeID = strings.TrimSpace(session.StoreID)
	}
	tenantID := strings.TrimSpace(session.TenantID)
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusOK, map[string]any{"results": []webAppReorder{}})
		return
	}
	reorders, err := fetchTopReorders(ctx, stringOrDefaultEnv("RECOMMENDATION_SERVICE_URL"), tenantID, customerID, storeID)
	if err != nil || len(reorders) == 0 {
		writeJSON(w, http.StatusOK, map[string]any{"results": []webAppReorder{}})
		return
	}
	meta, _ := fetchStoreMetadata(ctx, client, storeID)
	templates := reorders
	sort.Slice(templates, func(i, j int) bool {
		return templates[i].LastOrderedAt.After(templates[j].LastOrderedAt)
	})
	results := make([]webAppReorder, 0, len(templates))
	for _, t := range templates {
		results = append(results, toWebAppReorder(t, meta))
	}
	if len(results) > limit {
		results = results[:limit]
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results})
}
