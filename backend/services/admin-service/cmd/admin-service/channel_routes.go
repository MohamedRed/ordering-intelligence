package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func registerChannelRouteRoutes(router chi.Router, ctx context.Context, firestoreClient *cloudfirestore.Client) {
	router.Get("/channel-routes", func(w http.ResponseWriter, r *http.Request) {
		routes, err := listChannelRoutes(ctx, firestoreClient)
		if err != nil {
			log.Printf("failed to list channel routes: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
			return
		}
		writeJSON(w, http.StatusOK, routes)
	})

	router.Post("/channel-routes", func(w http.ResponseWriter, r *http.Request) {
		var payload channelRouteRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		payload.Channel = strings.TrimSpace(payload.Channel)
		payload.AccountID = strings.TrimSpace(payload.AccountID)
		payload.TenantID = strings.TrimSpace(payload.TenantID)
		payload.StoreID = strings.TrimSpace(payload.StoreID)
		payload.BusinessType = strings.TrimSpace(payload.BusinessType)
		payload.AgentID = strings.TrimSpace(payload.AgentID)

		if payload.Channel == "" || payload.AccountID == "" || payload.AgentID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		docID := strings.ToLower(payload.Channel) + "_" + payload.AccountID
		now := time.Now().UTC()
		doc := map[string]any{
			"id":            docID,
			"channel":       payload.Channel,
			"account_id":    payload.AccountID,
			"tenant_id":     payload.TenantID,
			"store_id":      payload.StoreID,
			"business_type": payload.BusinessType,
			"agent_id":      payload.AgentID,
			"updated_at":    now,
		}

		existing, err := firestoreClient.Collection(channelRoutesCollection).Doc(docID).Get(ctx)
		if err == nil && existing.Exists() {
			if createdAt, ok := existing.Data()["created_at"]; ok {
				doc["created_at"] = createdAt
			}
		} else if status.Code(err) == codes.NotFound || err == nil {
			doc["created_at"] = now
		} else if err != nil && status.Code(err) != codes.NotFound {
			log.Printf("failed to fetch channel route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}

		if _, err := firestoreClient.Collection(channelRoutesCollection).Doc(docID).Set(ctx, doc, cloudfirestore.MergeAll); err != nil {
			log.Printf("failed to upsert channel route: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "write_failed"})
			return
		}
		writeJSON(w, http.StatusOK, doc)
	})
}
