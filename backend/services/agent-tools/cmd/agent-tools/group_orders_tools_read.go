package main

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"golang.org/x/oauth2"
)

func registerGroupOrderReadTools(
	r chi.Router,
	cfg *serviceConfig,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
) {
	r.Get("/group-orders/join/{joinCode}", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:read") {
			return
		}
		joinCode := strings.TrimSpace(chi.URLParam(req, "joinCode"))
		if joinCode == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_join_code"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodGet, "/group_orders/join/"+joinCode, nil)
	})

	r.Get("/group-orders/{groupOrderId}", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:read") {
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		if groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodGet, "/group_orders/"+groupID, nil)
	})
}
