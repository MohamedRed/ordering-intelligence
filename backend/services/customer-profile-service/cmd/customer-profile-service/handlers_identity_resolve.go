package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

type resolveCustomerRequest struct {
	TenantID    string `json:"tenantId,omitempty"`
	Channel     string `json:"channel"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	StoreID     string `json:"storeId,omitempty"`
	Platform    string `json:"platform,omitempty"`
	Provider    string `json:"provider,omitempty"`
	AllowCreate *bool  `json:"allowCreate"`
}

func handleResolveCustomer(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var payload resolveCustomerRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.Channel = normalizeChannel(payload.Channel)
		payload.UserID = strings.TrimSpace(payload.UserID)
		payload.DisplayName = strings.TrimSpace(payload.DisplayName)
		payload.StoreID = strings.TrimSpace(payload.StoreID)
		payload.Platform = strings.TrimSpace(payload.Platform)
		payload.Provider = strings.TrimSpace(payload.Provider)
		if payload.Channel == "" || payload.UserID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_identity"})
			return
		}
		allowCreate := true
		if payload.AllowCreate != nil {
			allowCreate = *payload.AllowCreate
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		seen := buildSeenContext(payload.Channel, payload.StoreID, payload.Platform, payload.Provider)
		customer, identities, err := resolveCustomerForIdentity(ctx, fs, payload.Channel, payload.UserID, payload.DisplayName, allowCreate, seen)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			return
		}
		writeJSON(w, http.StatusOK, buildCustomerResponse(customer, identities))
	}
}

func handleGetCustomer(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		customerID := strings.TrimSpace(chi.URLParam(r, "customerId"))
		if customerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_customer"})
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		customer, err := resolveActiveCustomer(ctx, fs, customerID)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			return
		}
		identities, _ := listIdentitiesByCustomer(ctx, fs, customer.CustomerID)
		writeJSON(w, http.StatusOK, buildCustomerResponse(customer, identities))
	}
}
