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

func handleWebAppGroupOrderJoin(
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
	var payload webAppGroupOrderJoinRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.DisplayName = strings.TrimSpace(payload.DisplayName)
	payload.InviteID = strings.TrimSpace(payload.InviteID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if payload.InviteID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_invite"})
		return
	}
	if strings.TrimSpace(cfg.OrderServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	session, err := loadWebAppSession(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		if errors.Is(err, errWebAppSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}
	joinPayload := groupOrderJoinPayload{
		ParticipantID: strings.TrimSpace(session.UserID),
		Contact:       buildWebAppContact(session),
		DisplayName:   payload.DisplayName,
		InviteID:      payload.InviteID,
	}
	endpoint := fmt.Sprintf("%s/group_orders/%s/join", strings.TrimRight(cfg.OrderServiceURL, "/"), groupID)
	if err := proxyJSON(ctx, orderHTTPClient, http.MethodPost, endpoint, joinPayload, w); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
	}
}
