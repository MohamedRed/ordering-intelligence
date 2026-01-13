package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleOrdersEvents(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var env pubsubPushEnvelope
		if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_pubsub_envelope"})
			return
		}
		raw, err := base64.StdEncoding.DecodeString(env.Message.Data)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_base64"})
			return
		}
		var evt orderEvent
		if err := json.Unmarshal(raw, &evt); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_event_json"})
			return
		}
		evt.CustomerID = strings.TrimSpace(evt.CustomerID)
		if evt.CustomerID == "" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_identity"})
			return
		}

		name := strings.TrimSpace(evt.CustomerName)
		now := time.Now().UTC()
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		customer, err := resolveActiveCustomer(ctx, fs, evt.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusOK, map[string]string{"status": "customer_not_found"})
			return
		}

		updates := map[string]any{
			"lastSeenAt":  now,
			"updatedAt":   now,
			"lastOrderAt": evt.CreatedAt,
		}
		if name != "" && strings.TrimSpace(customer.DisplayName) == "" {
			updates["displayName"] = name
		}
		_, err = fs.Collection(customersCollection).Doc(customer.CustomerID).Set(ctx, updates, cloudfirestore.MergeAll)
		if err != nil {
			log.Printf("failed updating customer doc=%s err=%v", customer.CustomerID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "customer_update_failed"})
			return
		}
		meta := map[string]string{
			"storeId": strings.TrimSpace(evt.StoreID),
		}
		if strings.TrimSpace(evt.TenantID) != "" {
			meta["tenantId"] = strings.TrimSpace(evt.TenantID)
		}
		writeCustomerEvent(ctx, fs, customer.CustomerID, "order_recorded", "", "", meta)
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
}
