package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type webAppDeliveryPrewarmRequest struct {
	SessionID          string                 `json:"sessionId"`
	StoreID            string                 `json:"storeId,omitempty"`
	DropoffLatLng      *webAppDeliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress     *webAppDeliveryAddress `json:"dropoffAddress,omitempty"`
	DropoffAddressText string                 `json:"dropoffAddressText,omitempty"`
}

func handleWebAppDeliveryPrewarm(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	dispatchHTTPClient *http.Client,
) {
	if strings.TrimSpace(cfg.DispatchServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "dispatch_service_not_configured"})
		return
	}
	var payload webAppDeliveryPrewarmRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.DropoffAddressText = strings.TrimSpace(payload.DropoffAddressText)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		if status.Code(err) == codes.NotFound {
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

	body, _ := json.Marshal(map[string]any{
		"dropoffLatLng":      payload.DropoffLatLng,
		"dropoffAddress":     payload.DropoffAddress,
		"dropoffAddressText": payload.DropoffAddressText,
	})

	endpoint := strings.TrimRight(cfg.DispatchServiceURL, "/") + "/v1/stores/" + storeID + "/marketplace/prewarm"
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	client := dispatchHTTPClient
	if client == nil {
		client = &http.Client{Timeout: 12 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "dispatch_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "dispatch_prewarm_failed",
			"details": string(raw),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(raw)
}
