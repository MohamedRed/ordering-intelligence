package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppTestSessionRequest struct {
	Channel     string `json:"channel"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	StoreID     string `json:"storeId"`
	AccountID   string `json:"accountId"`
}

type webAppTestSessionResponse struct {
	SessionID  string `json:"sessionId"`
	CustomerID string `json:"customerId,omitempty"`
	Channel    string `json:"channel"`
	AccountID  string `json:"accountId"`
	UserID     string `json:"userId"`
	StoreID    string `json:"storeId,omitempty"`
}

func handleWebAppTestSession(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	if _, ok := requireInternalAuth(cfg, w, r); !ok {
		return
	}

	var payload webAppTestSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}

	channel := strings.TrimSpace(strings.ToLower(payload.Channel))
	if channel == "" {
		channel = "telegram_webapp"
	}
	switch channel {
	case "telegram_webapp", "discord_webapp", "snapchat_webapp":
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_channel"})
		return
	}

	userID := strings.TrimSpace(payload.UserID)
	if userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_user"})
		return
	}

	accountID := strings.TrimSpace(payload.AccountID)
	if accountID == "" {
		switch channel {
		case "discord_webapp":
			accountID = strings.TrimSpace(cfg.DiscordClientID)
			if accountID == "" {
				accountID = "discord_webapp"
			}
		case "snapchat_webapp":
			accountID = strings.TrimSpace(cfg.SnapchatClientID)
			if accountID == "" {
				accountID = "snapchat_webapp"
			}
		default:
			accountID = "telegram_webapp"
		}
	}

	displayName := strings.TrimSpace(payload.DisplayName)
	if displayName == "" {
		displayName = webAppDefaultCustomerName(channel)
	}

	storeID := strings.TrimSpace(payload.StoreID)
	storeMeta := storeMetadata{}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	if storeID != "" {
		meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
			return
		}
		storeMeta = meta
		if storeMeta.StoreID != "" {
			storeID = storeMeta.StoreID
		}
	}

	session := channelSession{
		Channel:        channel,
		AccountID:      accountID,
		UserID:         userID,
		DisplayName:    displayName,
		TenantID:       storeMeta.TenantID,
		StoreID:        storeID,
		BusinessType:   storeMeta.BusinessType,
		AuthProvider:   webAppAuthProvider(channel),
		ClientPlatform: "web",
		ClientApp:      "consumer-web",
		LastSeenAt:     time.Now().UTC(),
		CreatedAt:      time.Now().UTC(),
	}

	if customerID, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, session.TenantID, customerResolveContext{
		StoreID:  storeID,
		Platform: "web",
		Provider: session.AuthProvider,
	}); err == nil {
		session.CustomerID = customerID
	}

	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	writeJSON(w, http.StatusOK, webAppTestSessionResponse{
		SessionID:  sessionDocID(session.Channel, session.AccountID, session.UserID),
		CustomerID: session.CustomerID,
		Channel:    session.Channel,
		AccountID:  session.AccountID,
		UserID:     session.UserID,
		StoreID:    session.StoreID,
	})
}
