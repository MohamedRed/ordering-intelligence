package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

type webAppStoreDetailsResponse struct {
	StoreID                string `json:"storeId"`
	StoreName              string `json:"storeName"`
	TenantID               string `json:"tenantId"`
	BusinessType           string `json:"businessType"`
	LogoURL                string `json:"logoUrl"`
	Currency               string `json:"currency,omitempty"`
	FuelDefaultPrepayCents int64  `json:"fuelDefaultPrepayCents,omitempty"`
}

func handleWebAppStoreDetails(
	w http.ResponseWriter,
	r *http.Request,
	firestoreClient *cloudfirestore.Client,
) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
		return
	}

	writeJSON(w, http.StatusOK, webAppStoreDetailsResponse{
		StoreID:                meta.StoreID,
		StoreName:              meta.StoreName,
		TenantID:               meta.TenantID,
		BusinessType:           meta.BusinessType,
		LogoURL:                meta.LogoURL,
		Currency:               meta.Currency,
		FuelDefaultPrepayCents: meta.FuelDefaultPrepayCents,
	})
}
