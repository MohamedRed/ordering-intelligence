package main

import (
	"net/http"
	"strings"
	"time"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2"
	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"golang.org/x/oauth2"
)

func handleMarketplaceOrdersEvent(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	tasksClient *cloudtasks.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	order orderRecord,
) {
	status := strings.ToLower(strings.TrimSpace(order.Status))
	if status != "confirmed" && status != "ready" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "waiting"})
		return
	}
	ctx := r.Context()
	offer, err := createMarketplaceOfferForOrder(ctx, fs, cfg, pubsubClient, tasksClient, order)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "marketplace_offer_failed"})
		return
	}
	_ = patchOrderDelivery(ctx, httpClient, orderTokenSrc, cfg.OrderServiceURL, order.ID, map[string]any{
		"assignmentStatus": "pending",
		"offerCents":       offer.PayoutCents,
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"status":     "offer_created",
		"offerId":    offer.OfferID,
		"storeId":    offer.StoreID,
		"orderId":    order.ID,
		"expires":    offer.ExpiresAt.UTC().Format(time.RFC3339),
		"candidates": len(offer.CandidateIDs),
	})
}
