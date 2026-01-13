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

type mobileOrderOffSessionRequest struct {
	SessionID   string `json:"sessionId"`
	AmountCents int64  `json:"amountCents,omitempty"`
	Currency    string `json:"currency,omitempty"`
}

type mobileOffSessionPaymentResponse struct {
	Status         string `json:"status"`
	PaymentID      string `json:"paymentId,omitempty"`
	PaymentIntent  string `json:"paymentIntentId,omitempty"`
	ClientSecret   string `json:"clientSecret,omitempty"`
	CustomerID     string `json:"customerId,omitempty"`
	EphemeralKey   string `json:"ephemeralKey,omitempty"`
	StripeAccount  string `json:"stripeAccountId,omitempty"`
	PublishableKey string `json:"publishableKey,omitempty"`
	AmountCents    int64  `json:"amountCents,omitempty"`
	Currency       string `json:"currency,omitempty"`
	Error          string `json:"error,omitempty"`
}

func handleMobileOrderPayDefault(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
	orderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload mobileOrderOffSessionRequest
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
	}
	if payload.AmountCents > 0 {
		requestPayload["amountCents"] = payload.AmountCents
	}
	if strings.TrimSpace(payload.Currency) != "" {
		requestPayload["currency"] = strings.TrimSpace(payload.Currency)
	}
	body, _ := json.Marshal(requestPayload)
	endpoint := fmt.Sprintf(
		"%s/orders/%s/off-session",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		orderID,
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
			"error":   "off_session_failed",
			"details": string(respBody),
		})
		return
	}
	var result mobileOffSessionPaymentResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "off_session_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, result)
}
