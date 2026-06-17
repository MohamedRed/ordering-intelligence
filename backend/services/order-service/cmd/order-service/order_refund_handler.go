package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

type orderRefundRequest struct {
	AmountCents int64  `json:"amountCents,omitempty"`
	Reason      string `json:"reason,omitempty"`
	Note        string `json:"note,omitempty"`
	RequestedBy string `json:"requestedBy,omitempty"`
}

func handleOrderRefund(
	ctx context.Context,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
	orderID string,
) {
	if strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "payments_service_not_configured"})
		return
	}

	var payload orderRefundRequest
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
	payload.RequestedBy = strings.TrimSpace(authUID(r.Context()))

	record, err := fetchOrder(ctx, firestoreClient, orderID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
		return
	}
	if record == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), record.StoreID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	resp, err := doPaymentsJSONRequest(ctx, cfg, http.MethodPost, "/orders/"+orderID+"/refund", payload)
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
	var refundResult struct {
		PaymentStatus string `json:"paymentStatus"`
		RefundType    string `json:"refundType"`
	}
	if err := json.Unmarshal(respBody, &refundResult); err == nil {
		if refundResult.PaymentStatus == "refunded" || refundResult.RefundType == "void" {
			note := "Refunded"
			if payload.Note != "" {
				note = note + ": " + payload.Note
			}
			if _, err := markOrderRefunded(ctx, firestoreClient, orderID, r.Context(), cfg.RequireAuth, note); err != nil {
				log.Printf("refund status update failed: %v", err)
			}
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write(respBody)
}
