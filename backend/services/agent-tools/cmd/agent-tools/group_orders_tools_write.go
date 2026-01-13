package main

import (
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"golang.org/x/oauth2"
)

func registerGroupOrderWriteTools(
	r chi.Router,
	cfg *serviceConfig,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	paymentsTokenSrc oauth2.TokenSource,
) {
	r.Post("/group-orders", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		body, err := io.ReadAll(req.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodPost, "/group_orders", body)
	})

	r.Post("/group-orders/{groupOrderId}/join", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		body, err := io.ReadAll(req.Body)
		if err != nil || groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodPost, "/group_orders/"+groupID+"/join", body)
	})

	r.Post("/group-orders/{groupOrderId}/invites", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		body, err := io.ReadAll(req.Body)
		if err != nil || groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodPost, "/group_orders/"+groupID+"/invites", body)
	})

	r.Post("/group-orders/{groupOrderId}/items", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		body, err := io.ReadAll(req.Body)
		if err != nil || groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodPost, "/group_orders/"+groupID+"/items", body)
	})

	r.Post("/group-orders/{groupOrderId}/lock", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		body, err := io.ReadAll(req.Body)
		if err != nil || groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToOrderService(cfg, httpClient, orderTokenSrc, w, req, http.MethodPost, "/group_orders/"+groupID+"/lock", body)
	})

	r.Post("/group-orders/{groupOrderId}/checkout", func(w http.ResponseWriter, req *http.Request) {
		if !requireScopes(req.Context(), w, "group_orders:write") {
			return
		}
		if paymentsTokenSrc == nil || strings.TrimSpace(cfg.PaymentsServiceURL) == "" {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "payments_unavailable"})
			return
		}
		groupID := strings.TrimSpace(chi.URLParam(req, "groupOrderId"))
		body, err := io.ReadAll(req.Body)
		if err != nil || groupID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
			return
		}
		proxyToPaymentsService(cfg, httpClient, paymentsTokenSrc, w, req, http.MethodPost, "/group-orders/"+groupID+"/checkout", body)
	})
}
