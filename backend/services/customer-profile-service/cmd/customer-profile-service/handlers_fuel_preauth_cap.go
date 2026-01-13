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

type fuelPreauthCapRequest struct {
	FuelPreauthCapCents int64 `json:"fuelPreauthCapCents"`
}

func handleFuelPreauthCap(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		customerID := strings.TrimSpace(chi.URLParam(r, "customerId"))
		if customerID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_customer"})
			return
		}
		var payload fuelPreauthCapRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		capCents := payload.FuelPreauthCapCents
		if capCents < 0 {
			capCents = 0
		}

		ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
		defer cancel()

		customer, err := resolveActiveCustomer(ctx, fs, customerID)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			return
		}

		now := time.Now().UTC()
		updates := map[string]any{
			"fuelPreauthCapCents": capCents,
			"updatedAt":           now,
		}
		if _, err := fs.Collection(customersCollection).Doc(customer.CustomerID).Set(ctx, updates, cloudfirestore.MergeAll); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "customer_update_failed"})
			return
		}

		customer.FuelPreauthCapCents = capCents
		customer.UpdatedAt = now
		identities, _ := listIdentitiesByCustomer(ctx, fs, customer.CustomerID)
		writeJSON(w, http.StatusOK, buildCustomerResponse(customer, identities))
	}
}
