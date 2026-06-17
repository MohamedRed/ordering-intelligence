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
)

type mobileOrderPaymentIntentRequest struct {
	SessionID         string `json:"sessionId"`
	AmountCents       int64  `json:"amountCents,omitempty"`
	Currency          string `json:"currency,omitempty"`
	SavePaymentMethod *bool  `json:"savePaymentMethod,omitempty"`
}

type mobileOrderPaymentIntentResponse struct {
	PaymentID       string `json:"paymentId"`
	PaymentIntentID string `json:"paymentIntentId"`
	ClientSecret    string `json:"clientSecret"`
	CustomerID      string `json:"customerId"`
	EphemeralKey    string `json:"ephemeralKey"`
	StripeAccountID string `json:"stripeAccountId"`
	PublishableKey  string `json:"publishableKey"`
	AmountCents     int64  `json:"amountCents"`
	Currency        string `json:"currency"`
}

func handleMobileOrderPaymentIntent(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	paymentsHTTPClient *http.Client,
	orderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	var payload mobileOrderPaymentIntentRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomerFn(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if strings.TrimSpace(strings.ToLower(session.Channel)) != "mobile" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_channel"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
		return
	}
	if _, err := authorizeSessionOrder(ctx, cfg, orderHTTPClient, session, orderID); err != nil {
		writeWebAppOrderAccessError(w, err)
		return
	}

	requestPayload := map[string]any{
		"customerId":   customerID,
		"customerName": strings.TrimSpace(session.DisplayName),
		"sessionId":    payload.SessionID,
	}
	if payload.AmountCents > 0 {
		requestPayload["amountCents"] = payload.AmountCents
	}
	if strings.TrimSpace(payload.Currency) != "" {
		requestPayload["currency"] = strings.TrimSpace(payload.Currency)
	}
	if payload.SavePaymentMethod != nil {
		requestPayload["savePaymentMethod"] = *payload.SavePaymentMethod
	}

	body, _ := json.Marshal(requestPayload)
	endpoint := serviceURL(cfg.PaymentsServiceURL, "orders", orderID, "payment-intent")
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
			"error":   "payment_intent_failed",
			"details": string(respBody),
		})
		return
	}
	var paymentIntent mobileOrderPaymentIntentResponse
	if err := json.Unmarshal(respBody, &paymentIntent); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payment_intent_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, paymentIntent)
}
