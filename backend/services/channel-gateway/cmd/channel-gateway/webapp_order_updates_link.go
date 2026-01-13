package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func handleWebAppOrderUpdatesLink(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
) {
	orderID := strings.TrimSpace(chi.URLParam(r, "orderId"))
	if orderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_order_id"})
		return
	}
	var payload webAppOrderUpdatesLinkRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	session, err := loadWebAppSession(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		if errors.Is(err, errWebAppSessionNotFound) || status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}

	contact := channelContact{
		Channel:     "telegram",
		AccountID:   strings.TrimSpace(session.AccountID),
		UserID:      strings.TrimSpace(session.UserID),
		ThreadID:    strings.TrimSpace(session.ThreadID),
		DisplayName: strings.TrimSpace(session.DisplayName),
	}

	if err := updateOrderChannelContact(ctx, cfg, orderHTTPClient, orderID, contact); err != nil {
		switch {
		case errors.Is(err, errOrderContactUpdateNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "order_not_found"})
		case errors.Is(err, errOrderContactUpdateConflict):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "channel_contact_exists"})
		case errors.Is(err, errOrderContactUpdateUnavailable):
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_service_not_configured"})
		default:
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_contact_update_failed"})
		}
		return
	}

	resp := webAppOrderUpdatesLinkResponse{Linked: true}
	if cfg.TelegramBotToken == "" {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	chatID, err := strconv.ParseInt(contact.UserID, 10, 64)
	if err != nil {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	message := "You're all set — we'll send updates for your order here."
	if err := sendTelegramMessage(ctx, cfg.TelegramBotToken, chatID, contact.ThreadID, message); err != nil {
		if requiresTelegramStart(err) {
			resp.NeedsUserStart = true
		} else {
			log.Printf("telegram updates confirmation failed order=%s err=%v", orderID, err)
		}
		writeJSON(w, http.StatusOK, resp)
		return
	}
	resp.MessageSent = true
	writeJSON(w, http.StatusOK, resp)
}
