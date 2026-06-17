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

func handleGroupOrderInviteCreate(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client, cfg *serviceConfig) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload groupOrderInviteCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	requesterID := participantIDFromContact(payload.Contact, payload.ParticipantID)
	if requesterID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_participant"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	session, err := fetchGroupOrderFn(ctx, client, groupID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	if !requireGroupOrderSessionAccess(w, r, cfg, session) {
		return
	}
	hostID := participantIDFromContact(session.Host, "")
	if requesterID != hostID {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not_group_host"})
		return
	}
	ttl := payload.ExpiresInMins
	if ttl <= 0 {
		ttl = defaultInviteTTLMinutes
	}
	maxUses := payload.MaxUses
	if maxUses < 0 {
		maxUses = 0
	}
	invite := groupOrderInvite{
		InviteID:     newGroupOrderInviteID(),
		GroupOrderID: session.ID,
		CreatedByID:  requesterID,
		CreatedAt:    time.Now().UTC(),
		ExpiresAt:    time.Now().UTC().Add(time.Duration(ttl) * time.Minute),
		MaxUses:      maxUses,
	}
	if err := createGroupOrderInvite(ctx, client, invite); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "invite_create_failed"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderInviteResponse{Invite: invite})
}
