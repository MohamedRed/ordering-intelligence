package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/api/iterator"
)

func handleGroupOrderLookup(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client, cfg *serviceConfig) {
	code := strings.ToUpper(strings.TrimSpace(chi.URLParam(r, "joinCode")))
	if code == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_join_code"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	iter := client.Collection(groupOrdersCollection).Where("joinCode", "==", code).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err == iterator.Done {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "lookup_failed"})
		return
	}
	var session groupOrderSession
	if err := doc.DataTo(&session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "decode_failed"})
		return
	}
	if !requireGroupOrderSessionAccess(w, r, cfg, session) {
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
}
