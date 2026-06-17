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
	"github.com/go-chi/chi/v5"
)

func handleWebAppGroupOrderCheckout(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	paymentsHTTPClient *http.Client,
) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload webAppGroupOrderCheckoutRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	payload.SuccessURL = strings.TrimSpace(payload.SuccessURL)
	payload.CancelURL = strings.TrimSpace(payload.CancelURL)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if payload.SuccessURL == "" || payload.CancelURL == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_redirect_urls"})
		return
	}
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()
	session, err := loadWebAppSessionFn(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		if errors.Is(err, errWebAppSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}
	if _, err := authorizeWebAppGroupOrder(ctx, cfg, orderHTTPClient, session, groupID, groupOrderAccessParticipant); err != nil {
		writeWebAppGroupOrderAccessError(w, err)
		return
	}
	endpoint := fmt.Sprintf("%s/group-orders/%s/checkout", strings.TrimRight(cfg.PaymentsServiceURL, "/"), groupID)
	checkoutPayload := map[string]string{
		"successUrl": payload.SuccessURL,
		"cancelUrl":  payload.CancelURL,
	}
	if payload.ParticipantID != "" {
		participantID, err := resolveSessionParticipantID(session, payload.ParticipantID)
		if err != nil {
			writeWebAppGroupOrderAccessError(w, err)
			return
		}
		checkoutPayload["participantId"] = participantID
	}
	if payload.Currency != "" {
		checkoutPayload["currency"] = payload.Currency
	}
	if err := proxyJSON(ctx, paymentsHTTPClient, http.MethodPost, endpoint, checkoutPayload, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
	}
}
