package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleWebAppGroupOrderCreate(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
) {
	var payload webAppGroupOrderCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.PaymentMode = strings.TrimSpace(payload.PaymentMode)
	payload.PaymentMethod = strings.TrimSpace(payload.PaymentMethod)
	payload.DisplayName = strings.TrimSpace(payload.DisplayName)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	session, err := loadWebAppSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		if errors.Is(err, errWebAppSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}
	storeID := payload.StoreID
	if storeID == "" {
		storeID = strings.TrimSpace(session.StoreID)
	}
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store"})
		return
	}
	tenantID := strings.TrimSpace(session.TenantID)
	if tenantID == "" {
		meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
			return
		}
		tenantID = strings.TrimSpace(meta.TenantID)
	}
	if tenantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_tenant"})
		return
	}
	host := buildWebAppContact(session)
	createPayload := groupOrderCreatePayload{
		TenantID:        tenantID,
		StoreID:         storeID,
		CustomerID:      strings.TrimSpace(session.CustomerID),
		FulfillmentType: strings.TrimSpace(payload.FulfillmentType),
		PaymentMode:     payload.PaymentMode,
		PaymentMethod:   payload.PaymentMethod,
		Host:            host,
		ParticipantID:   strings.TrimSpace(session.UserID),
		DisplayName:     payload.DisplayName,
	}
	endpoint := fmt.Sprintf("%s/group_orders", strings.TrimRight(cfg.OrderServiceURL, "/"))
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodPost, endpoint, createPayload, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}
