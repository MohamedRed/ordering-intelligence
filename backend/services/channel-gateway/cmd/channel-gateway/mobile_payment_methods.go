package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type mobilePaymentMethodsResponse struct {
	Methods []map[string]any `json:"methods"`
}

type mobilePaymentMethodsRequest struct {
	SessionID       string `json:"sessionId"`
	PaymentMethodID string `json:"paymentMethodId"`
}

type mobileSetupIntentResponse struct {
	SetupIntentID  string `json:"setupIntentId"`
	ClientSecret   string `json:"clientSecret"`
	CustomerID     string `json:"customerId"`
	EphemeralKey   string `json:"ephemeralKey"`
	StripeAccount  string `json:"stripeAccountId"`
	PublishableKey string `json:"publishableKey"`
}

func handleMobilePaymentMethodsList(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, sessionID)
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
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	endpoint := fmt.Sprintf(
		"%s/customers/%s/payment-methods?tenantId=%s",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		url.PathEscape(customerID),
		url.QueryEscape(strings.TrimSpace(session.TenantID)),
	)
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	resp, err := paymentsHTTPClient.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "payment_methods_failed",
			"details": string(body),
		})
		return
	}
	var payload mobilePaymentMethodsResponse
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payment_methods_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, payload)
}

func handleMobilePaymentSetupIntent(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload mobilePaymentMethodsRequest
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
		"tenantId":    strings.TrimSpace(session.TenantID),
		"customerName": strings.TrimSpace(session.DisplayName),
	}
	body, _ := json.Marshal(requestPayload)
	endpoint := fmt.Sprintf(
		"%s/customers/%s/setup-intent",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		url.PathEscape(customerID),
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
			"error":   "setup_intent_failed",
			"details": string(respBody),
		})
		return
	}
	var setupIntent mobileSetupIntentResponse
	if err := json.Unmarshal(respBody, &setupIntent); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "setup_intent_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, setupIntent)
}

func handleMobilePaymentDefault(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	paymentsHTTPClient *http.Client,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload mobilePaymentMethodsRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.PaymentMethodID = strings.TrimSpace(payload.PaymentMethodID)
	if payload.SessionID == "" || payload.PaymentMethodID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
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
		"tenantId":         strings.TrimSpace(session.TenantID),
		"paymentMethodId":  payload.PaymentMethodID,
	}
	body, _ := json.Marshal(requestPayload)
	endpoint := fmt.Sprintf(
		"%s/customers/%s/payment-methods/default",
		strings.TrimRight(cfg.PaymentsServiceURL, "/"),
		url.PathEscape(customerID),
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
			"error":   "default_payment_failed",
			"details": string(respBody),
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
