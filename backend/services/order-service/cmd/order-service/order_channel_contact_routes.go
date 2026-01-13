package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"github.com/go-chi/chi/v5"
)

type orderChannelContactUpdateRequest struct {
	Channel     string `json:"channel"`
	AccountID   string `json:"accountId,omitempty"`
	UserID      string `json:"userId"`
	ThreadID    string `json:"threadId,omitempty"`
	DisplayName string `json:"displayName,omitempty"`
	Locale      string `json:"locale,omitempty"`
}

func registerOrderChannelContactRoutes(
	router chi.Router,
	firestoreClient *cloudfirestore.Client,
	pubsubClient *cloudpubsub.Client,
	cfg *serviceConfig,
) {
	router.Patch("/orders/{orderID}/channel-contact", func(w http.ResponseWriter, r *http.Request) {
		orderID := strings.TrimSpace(chi.URLParam(r, "orderID"))
		if orderID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
			return
		}
		var payload orderChannelContactUpdateRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		contact, err := normalizeOrderChannelContact(payload)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_channel_contact"})
			return
		}
		updated, err := updateOrderChannelContact(r.Context(), firestoreClient, orderID, contact, r.Context(), cfg.RequireAuth)
		if err != nil {
			switch {
			case errors.Is(err, errOrderNotFound):
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
			case errors.Is(err, errUnauthorizedStore):
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
			case errors.Is(err, errOrderContactConflict):
				writeJSON(w, http.StatusConflict, map[string]string{"error": "channel_contact_exists"})
			case errors.Is(err, errInvalidChannelContact):
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_channel_contact"})
			default:
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "update_failed"})
			}
			return
		}

		if pubsubClient != nil && cfg.OrdersTopic != "" {
			if err := publishOrderEvent(r.Context(), pubsubClient, cfg.OrdersTopic, *updated); err != nil {
				log.Printf("failed to publish order event: %v", err)
			}
		}

		writeJSON(w, http.StatusOK, updated)
	})
}

func normalizeOrderChannelContact(payload orderChannelContactUpdateRequest) (channelContact, error) {
	contact := channelContact{
		Channel:     strings.ToLower(strings.TrimSpace(payload.Channel)),
		AccountID:   strings.TrimSpace(payload.AccountID),
		UserID:      strings.TrimSpace(payload.UserID),
		ThreadID:    strings.TrimSpace(payload.ThreadID),
		DisplayName: strings.TrimSpace(payload.DisplayName),
		Locale:      strings.TrimSpace(payload.Locale),
	}
	if contact.Channel == "" || contact.UserID == "" {
		return channelContact{}, errInvalidChannelContact
	}
	if contact.Channel != "telegram" {
		return channelContact{}, errInvalidChannelContact
	}
	return contact, nil
}
