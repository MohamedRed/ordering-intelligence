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

func handleWebAppGroupOrderSubmit(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload webAppGroupOrderSubmitRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
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
	if _, err := authorizeWebAppGroupOrder(ctx, cfg, orderHTTPClient, session, groupID, groupOrderAccessHost); err != nil {
		writeWebAppGroupOrderAccessError(w, err)
		return
	}
	endpoint := fmt.Sprintf("%s/group_orders/%s/submit", strings.TrimRight(cfg.OrderServiceURL, "/"), groupID)
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodPost, endpoint, map[string]string{}, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}
