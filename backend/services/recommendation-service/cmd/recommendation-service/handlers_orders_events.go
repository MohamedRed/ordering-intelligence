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
			log.Printf("skipping malformed recommendation orders Pub/Sub event reason=%s err=%v", reason, err)
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_invalid_pubsub", "reason": reason})
			return
		}
		evt.CustomerID = strings.TrimSpace(evt.CustomerID)
		evt.StoreID = strings.TrimSpace(evt.StoreID)
		if evt.CustomerID == "" || evt.StoreID == "" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_missing_identity"})
			return
		}
		hasFuel := evt.Fuel != nil && strings.EqualFold(strings.TrimSpace(evt.BusinessType), "gas_station")
		if len(evt.Items) == 0 && !hasFuel {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_no_items"})
			return
		}

		var templateID string
		var title string
		var items []orderItem
		var fuel *fuelOrder
		if len(evt.Items) > 0 {
			templateID = orderTemplateID(evt.Items)
			title = templateTitle(evt.Items)
			items = evt.Items
		} else if hasFuel {
			templateID = fuelTemplateID(*evt.Fuel)
			title = fuelTemplateTitle(*evt.Fuel)
			fuel = evt.Fuel
		}

		docID := reordersDocID(evt.CustomerID, evt.StoreID)
		now := time.Now().UTC()
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		err := fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
			ref := fs.Collection(reordersCollection).Doc(docID)
			snap, err := tx.Get(ref)
			var existing reorderDoc
			if err == nil && snap.Exists() {
				_ = snap.DataTo(&existing)
			}

			// Update last-3-distinct list.
			next := upsertLastDistinct(existing.TopReorders, reorderTemplate{
				OrderTemplateID: templateID,
				Title:           title,
				Items:           items,
				Fuel:            fuel,
				LastOrderedAt:   evt.CreatedAt,
			})

			payload := map[string]any{
				"storeId":     evt.StoreID,
				"customerId":  evt.CustomerID,
				"topReorders": next,
				"updatedAt":   now,
			}
			return tx.Set(ref, payload, cloudfirestore.MergeAll)
		})
		if err != nil {
			log.Printf("failed updating reorders doc=%s err=%v", docID, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
}
