package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type unlinkRequest struct {
	TenantID   string `json:"tenantId,omitempty"`
	CustomerID string `json:"customerId"`
	Channel    string `json:"channel"`
	UserID     string `json:"userId"`
}

func handleUnlink(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var payload unlinkRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.CustomerID = strings.TrimSpace(payload.CustomerID)
		payload.Channel = normalizeChannel(payload.Channel)
		payload.UserID = strings.TrimSpace(payload.UserID)
		if payload.CustomerID == "" || payload.Channel == "" || payload.UserID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_unlink_fields"})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
		defer cancel()
		customer, err := resolveActiveCustomer(ctx, fs, payload.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			return
		}
		identity, found, err := fetchIdentity(ctx, fs, payload.Channel, payload.UserID)
		if err != nil || !found || identity.CustomerID != customer.CustomerID {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "identity_not_found"})
			return
		}
		count, err := countIdentities(ctx, fs, customer.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "identity_count_failed"})
			return
		}
		if count <= 1 {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "cannot_unlink_last_identity"})
			return
		}
		if err := deleteIdentity(ctx, fs, payload.Channel, payload.UserID); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "unlink_failed"})
			return
		}

		writeCustomerEvent(ctx, fs, customer.CustomerID, "identity_unlinked", payload.Channel, payload.UserID, nil)
		identities, _ := listIdentitiesByCustomer(ctx, fs, customer.CustomerID)
		writeJSON(w, http.StatusOK, buildCustomerResponse(customer, identities))
	}
}
