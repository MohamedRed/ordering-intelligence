package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func registerHealthRoutes(router chi.Router, cfg *serviceConfig) {
	router.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"status":      "ok",
			"service":     "admin-service",
			"environment": cfg.Environment,
		})
	})
}

func registerTenantRoutes(router chi.Router, ctx context.Context, firestoreClient *cloudfirestore.Client) {
	router.Get("/tenants", func(w http.ResponseWriter, r *http.Request) {
		tenants, err := listTenants(ctx, firestoreClient)
		if err != nil {
			log.Printf("failed to list tenants: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
			return
		}
		writeJSON(w, http.StatusOK, tenants)
	})

	router.Post("/tenants", func(w http.ResponseWriter, r *http.Request) {
		var payload tenantRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		if payload.Name == "" || payload.PrimaryUser == "" || payload.StoreID == "" || payload.BusinessType == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
			return
		}

		tenantRecord := tenant{
			ID:           generateTenantID(),
			Name:         payload.Name,
			PrimaryUser:  payload.PrimaryUser,
			Status:       defaultStatus(payload.Status),
			FeatureFlags: payload.FeatureFlags,
			StoreID:      payload.StoreID,
			BusinessType: payload.BusinessType,
			Timezone:     payload.Timezone,
			Phone:        payload.Phone,
			CreatedAt:    time.Now().UTC(),
			UpdatedAt:    time.Now().UTC(),
		}

		if err := createTenant(ctx, firestoreClient, tenantRecord); err != nil {
			log.Printf("failed to create tenant: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "create_failed"})
			return
		}

		_ = logAudit(ctx, firestoreClient, "tenant_created", tenantRecord.ID, payload.PrimaryUser)
		writeJSON(w, http.StatusCreated, tenantRecord)
	})

	router.Get("/tenants/{tenantID}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "tenantID")
		if id == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_tenant_id"})
			return
		}

		record, err := fetchTenant(ctx, firestoreClient, id)
		if err != nil {
			log.Printf("failed to fetch tenant: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
			return
		}
		if record == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			return
		}

		writeJSON(w, http.StatusOK, record)
	})

	router.Patch("/tenants/{tenantID}/feature-flags", func(w http.ResponseWriter, r *http.Request) {
		tenantID := chi.URLParam(r, "tenantID")
		if tenantID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_tenant_id"})
			return
		}

		var payload map[string]bool
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}

		updated, err := updateTenantFlags(ctx, firestoreClient, tenantID, payload)
		if err != nil {
			if errors.Is(err, errTenantNotFound) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
				return
			}
			log.Printf("failed updating flags: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}

		_ = logAudit(ctx, firestoreClient, "flags_updated", tenantID, "system")
		writeJSON(w, http.StatusOK, updated)
	})
}
