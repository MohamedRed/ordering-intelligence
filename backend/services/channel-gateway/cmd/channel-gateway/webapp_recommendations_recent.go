package main

import (
	"context"
	"net/http"
	"sort"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleWebAppRecentReorders(
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
	limit := limitFromQuery(r, 3)
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, client, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusOK, map[string]any{"results": []webAppReorder{}})
		return
	}
	reorderDocs, err := fetchReorderDocsByCustomerID(ctx, client, customerID)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"results": []webAppReorder{}})
		return
	}
	storeCache := map[string]storeMetadata{}
	results := []webAppReorder{}
	for _, rd := range reorderDocs {
		meta, ok := storeCache[rd.StoreID]
		if !ok {
			meta, _ = fetchStoreMetadata(ctx, client, rd.StoreID)
			storeCache[rd.StoreID] = meta
		}
		for _, t := range rd.TopReorders {
			results = append(results, toWebAppReorder(t, meta))
		}
	}
	sort.Slice(results, func(i, j int) bool {
		return results[i].OrderedAt > results[j].OrderedAt
	})
	if len(results) > limit {
		results = results[:limit]
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results})
}
