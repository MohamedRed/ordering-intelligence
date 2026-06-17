package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func handleGroupOrderAddItems(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client, cfg *serviceConfig) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload groupOrderAddItemsRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	payload.ParticipantLabel = strings.TrimSpace(payload.ParticipantLabel)
	if payload.ParticipantID == "" || len(payload.Items) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_items"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	updated, err := updateGroupOrderWithStoreAccess(ctx, client, groupID, r.Context(), cfg, func(current groupOrderSession) (groupOrderSession, error) {
		if current.Status != groupOrderStatusOpen {
			return current, errInvalidGroupStatus
		}
		found := false
		for _, participant := range current.Participants {
			if participant.ParticipantID == payload.ParticipantID {
				found = true
				break
			}
		}
		if !found {
			return current, errParticipantNotFound
		}
		for i := range payload.Items {
			payload.Items[i].ParticipantID = payload.ParticipantID
			payload.Items[i].ParticipantLabel = payload.ParticipantLabel
		}
		current.Items = append(current.Items, payload.Items...)
		return current, nil
	})
	if err != nil {
		if errors.Is(err, errUnauthorizedStore) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			return
		}
		if errorsIsInvalidStatus(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "group_order_locked"})
			return
		}
		if errorsIsParticipantMissing(err) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "participant_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_add_failed"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: updated})
}
