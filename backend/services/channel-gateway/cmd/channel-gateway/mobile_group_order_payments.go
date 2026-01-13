package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type mobileGroupOrderPaymentRequest struct {
	SessionID       string `json:"sessionId"`
	ParticipantID   string `json:"participantId,omitempty"`
	Currency        string `json:"currency,omitempty"`
	SavePaymentMethod *bool `json:"savePaymentMethod,omitempty"`
}

func handleMobileGroupOrderPaymentIntent(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
	groupOrderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload mobileGroupOrderPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if strings.ToLower(strings.TrimSpace(session.Channel)) != "mobile" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_channel"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
		return
	}
	requestPayload := map[string]any{
		"customerId":   customerID,
		"customerName": strings.TrimSpace(session.DisplayName),
		"sessionId":    payload.SessionID,
		"tenantId":     strings.TrimSpace(session.TenantID),
		"participantId": strings.TrimSpace(payload.ParticipantID),
	}
	if strings.TrimSpace(payload.Currency) != "" {
		requestPayload["currency"] = strings.TrimSpace(payload.Currency)
	}
	if payload.SavePaymentMethod != nil {
		requestPayload["savePaymentMethod"] = *payload.SavePaymentMethod
	}
	body, _ := json.Marshal(requestPayload)
	endpoint := fmt.Sprintf(
		"%s/group-orders/%s/payment-intent",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		groupOrderID,
	)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := paymentsHTTPClient.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "group_order_intent_failed",
			"details": string(respBody),
		})
		return
	}
	var paymentIntent mobileOrderPaymentIntentResponse
	if err := json.Unmarshal(respBody, &paymentIntent); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_intent_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, paymentIntent)
}

func handleMobileGroupOrderPayDefault(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
	groupOrderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload mobileGroupOrderPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if strings.ToLower(strings.TrimSpace(session.Channel)) != "mobile" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_channel"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
		return
	}
	requestPayload := map[string]any{
		"customerId":   customerID,
		"customerName": strings.TrimSpace(session.DisplayName),
		"sessionId":    payload.SessionID,
		"tenantId":     strings.TrimSpace(session.TenantID),
		"participantId": strings.TrimSpace(payload.ParticipantID),
	}
	if strings.TrimSpace(payload.Currency) != "" {
		requestPayload["currency"] = strings.TrimSpace(payload.Currency)
	}
	body, _ := json.Marshal(requestPayload)
	endpoint := fmt.Sprintf(
		"%s/group-orders/%s/off-session",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		groupOrderID,
	)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := paymentsHTTPClient.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "group_order_off_session_failed",
			"details": string(respBody),
		})
		return
	}
	var result mobileOffSessionPaymentResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_off_session_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, result)
}
