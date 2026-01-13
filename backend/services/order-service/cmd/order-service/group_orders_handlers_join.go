package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func handleGroupOrderJoin(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload groupOrderJoinRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	payload.DisplayName = strings.TrimSpace(payload.DisplayName)
	payload.InviteID = strings.TrimSpace(payload.InviteID)
	participantID := participantIDFromContact(payload.Contact, payload.ParticipantID)
	if participantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_participant"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	updated, err := joinGroupOrderWithInvite(
		ctx,
		client,
		groupID,
		payload.InviteID,
		participantID,
		payload.DisplayName,
		payload.Contact,
	)
	if err != nil {
		if errorsIsInvalidStatus(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "group_order_closed"})
			return
		}
		if errorsIsInviteNotFound(err) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invite_required"})
			return
		}
		if errorsIsInviteExpired(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "invite_expired"})
			return
		}
		if errorsIsInviteLimitReached(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "invite_limit_reached"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_join_failed"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: updated})
}
