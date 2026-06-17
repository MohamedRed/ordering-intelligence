package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

const (
	menuUpdateDecodeInvalidPayload = "invalid_payload"
	menuUpdateDecodeMissingData    = "missing_data"
	menuUpdateDecodeBadBase64      = "bad_base64"
	menuUpdateDecodeInvalidEvent   = "invalid_event"
)

type menuUpdateEvent struct {
	StoreID   string    `json:"storeId"`
	UpdatedAt time.Time `json:"updatedAt"`
	JobID     string    `json:"jobId"`
	Source    string    `json:"source"`
}

type menuUpdatePushEnvelope struct {
	Message struct {
		Data string `json:"data"`
	} `json:"message"`
}

func decodeMenuUpdateEvent(body io.Reader) (menuUpdateEvent, string, error) {
	var payload menuUpdatePushEnvelope
	if err := json.NewDecoder(body).Decode(&payload); err != nil {
		return menuUpdateEvent{}, menuUpdateDecodeInvalidPayload, err
	}
	data := strings.TrimSpace(payload.Message.Data)
	if data == "" {
		return menuUpdateEvent{}, menuUpdateDecodeMissingData, errors.New("pubsub message data is empty")
	}
	dataBytes, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return menuUpdateEvent{}, menuUpdateDecodeBadBase64, err
	}
	var evt menuUpdateEvent
	if err := json.Unmarshal(dataBytes, &evt); err != nil {
		return menuUpdateEvent{}, menuUpdateDecodeInvalidEvent, fmt.Errorf("decode menu update event: %w", err)
	}
	if strings.TrimSpace(evt.StoreID) == "" {
		return menuUpdateEvent{}, menuUpdateDecodeInvalidEvent, errors.New("storeId is required")
	}
	evt.StoreID = strings.TrimSpace(evt.StoreID)
	return evt, "", nil
}

// menuUpdatesHandler processes Pub/Sub push payloads to invalidate/prime menu cache.
func menuUpdatesHandler(ctx context.Context, firestoreClient *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		evt, reason, err := decodeMenuUpdateEvent(r.Body)
		if err != nil {
			log.Printf("skipping malformed menu update Pub/Sub event reason=%s err=%v", reason, err)
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored_invalid_pubsub", "reason": reason})
			return
		}
		log.Printf("menu-update event received store=%s source=%s updatedAt=%s job=%s", evt.StoreID, evt.Source, evt.UpdatedAt, evt.JobID)
		invalidateMenuCache(evt.StoreID)
		// Optionally pre-warm cache
		if _, err := fetchMenuCached(ctx, firestoreClient, evt.StoreID); err != nil {
			log.Printf("menu-update prefetch failed: %v", err)
		}
		w.WriteHeader(http.StatusNoContent)
	}
}
