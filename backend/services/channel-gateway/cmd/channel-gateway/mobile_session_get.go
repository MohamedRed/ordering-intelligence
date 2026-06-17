package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleMobileSessionGet(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_id"})
		return
	}
	if !verifyMobileSessionRequestAuth(cfg, w, r, sessionID, "", "") {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}

	storeID := strings.TrimSpace(session.StoreID)
	storeMeta := storeMetadata{}
	if storeID != "" {
		if meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID); err == nil {
			storeMeta = meta
			storeID = meta.StoreID
		}
	}

	session.LastSeenAt = time.Now().UTC()
	_ = upsertSession(ctx, firestoreClient, session)

	var fuelPreauthCap int64
	if session.CustomerID != "" {
		if profile, err := fetchCustomerProfile(ctx, cfg.CustomerProfileServiceURL, session.CustomerID); err == nil {
			fuelPreauthCap = profile.FuelPreauthCapCents
		}
	}

	writeJSON(w, http.StatusOK, mobileSessionStartResponse{
		SessionID:              sessionID,
		AccountID:              session.AccountID,
		UserID:                 session.UserID,
		DisplayName:            session.DisplayName,
		StoreID:                storeID,
		StoreName:              storeMeta.StoreName,
		TenantID:               session.TenantID,
		CustomerID:             session.CustomerID,
		BusinessType:           session.BusinessType,
		Currency:               storeMeta.Currency,
		FuelDefaultPrepayCents: storeMeta.FuelDefaultPrepayCents,
		FuelPreauthCapCents:    fuelPreauthCap,
	})
}
