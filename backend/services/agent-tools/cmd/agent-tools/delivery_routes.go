package main

import (
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/go-chi/chi/v5"
	"golang.org/x/oauth2"
)

func handleDeliveryQuote(
	cfg *serviceConfig,
	client *http.Client,
	dispatchTokenSrc oauth2.TokenSource,
	deliveryTokenSrc oauth2.TokenSource,
	w http.ResponseWriter,
	r *http.Request,
) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if !requireScopes(r.Context(), w, "orders:write") {
		return
	}
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_body"})
		return
	}
	if strings.TrimSpace(cfg.DeliveryServiceURL) != "" && deliveryTokenSrc != nil {
		path := "/v1/stores/" + url.PathEscape(storeID) + "/delivery/quote"
		proxyToDeliveryService(cfg, client, deliveryTokenSrc, w, r, http.MethodPost, path, body)
		return
	}
	if strings.TrimSpace(cfg.DispatchServiceURL) == "" || dispatchTokenSrc == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "dispatch_service_not_configured"})
		return
	}
	path := "/v1/stores/" + url.PathEscape(storeID) + "/quote"
	proxyToDispatchService(cfg, client, dispatchTokenSrc, w, r, http.MethodPost, path, body)
}
