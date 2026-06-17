package main

import (
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"golang.org/x/oauth2"
)

func handleMarketplaceFinalize(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	offerID string,
) {
	offerID = strings.TrimSpace(offerID)
	if offerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_offer_id"})
		return
	}
	if err := finalizeMarketplaceOffer(r.Context(), fs, cfg, pubsubClient, httpClient, orderTokenSrc, offerID); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "finalize_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
