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

type groupOrderRefundRequest struct {
	AmountCents  int64  `json:"amountCents,omitempty"`
	Reason       string `json:"reason,omitempty"`
	Note         string `json:"note,omitempty"`
	RequestedBy  string `json:"requestedBy,omitempty"`
	PaymentID    string `json:"paymentId,omitempty"`
	ParticipantID string `json:"participantId,omitempty"`
}

func handleGroupOrderRefund(
	ctx context.Context,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
	groupOrderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}
	var payload groupOrderRefundRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil && err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if payload.AmountCents < 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_amount"})
		return
	}
	payload.Reason = strings.TrimSpace(payload.Reason)
	payload.Note = strings.TrimSpace(payload.Note)
	payload.PaymentID = strings.TrimSpace(payload.PaymentID)
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	payload.RequestedBy = strings.TrimSpace(authUID(r.Context()))
	if payload.PaymentID == "" && payload.ParticipantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_payment_reference"})
		return
	}

	session, err := fetchGroupOrder(ctx, firestoreClient, groupOrderID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), session.StoreID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	body, _ := json.Marshal(payload)
	endpoint := strings.TrimRight(cfg.PaymentsServiceURL, "/") + "/group-orders/" + groupOrderID + "/refund"
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 12 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_service_unavailable"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		writeJSON(w, resp.StatusCode, map[string]any{
			"error":   "refund_failed",
			"details": string(respBody),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(respBody)
}
