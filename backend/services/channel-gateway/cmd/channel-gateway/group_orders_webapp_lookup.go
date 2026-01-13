package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

func handleWebAppGroupOrderLookup(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	orderHTTPClient *http.Client,
) {
	joinCode := strings.TrimSpace(chi.URLParam(r, "joinCode"))
	if joinCode == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_join_code"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	endpoint := fmt.Sprintf("%s/group_orders/join/%s", strings.TrimRight(cfg.OrderServiceURL, "/"), joinCode)
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodGet, endpoint, nil, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}

func handleWebAppGroupOrderGet(
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
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	endpoint := fmt.Sprintf("%s/group_orders/%s", strings.TrimRight(cfg.OrderServiceURL, "/"), groupID)
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodGet, endpoint, nil, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}
