package main

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleOrdersEvents(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var evt orderEvent
		if reason, err := decodePubSubPushJSON(r.Body, &evt); err != nil {
			log.Printf("skipping malformed customer profile orders Pub/Sub event reason=%s err=%v", reason, err)
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_invalid_pubsub", "reason": reason})
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
