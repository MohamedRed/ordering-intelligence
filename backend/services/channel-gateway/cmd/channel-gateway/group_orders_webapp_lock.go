package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

func handleWebAppGroupOrderLock(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	orderHTTPClient *http.Client,
) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload webAppGroupOrderLockRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	endpoint := fmt.Sprintf("%s/group_orders/%s/lock", strings.TrimRight(cfg.OrderServiceURL, "/"), groupID)
	lockPayload := map[string]int64{
		"taxCents":      payload.TaxCents,
		"feeCents":      payload.FeeCents,
		"discountCents": payload.DiscountCents,
	}
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodPost, endpoint, lockPayload, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}
