package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleDiscordWebAppSessionStart(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload discordWebAppSessionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.Code = strings.TrimSpace(payload.Code)
	payload.RedirectURI = strings.TrimSpace(payload.RedirectURI)
	payload.AccessToken = strings.TrimSpace(payload.AccessToken)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.Locale = strings.TrimSpace(payload.Locale)

	if payload.Code == "" && payload.AccessToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_code"})
		return
	}
	if cfg.DiscordClientID == "" || cfg.DiscordClientSecret == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "discord_not_configured"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	token := payload.AccessToken
	if token == "" {
		var err error
		token, err = exchangeDiscordOAuthToken(ctx, cfg, payload.Code, payload.RedirectURI)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "discord_oauth_failed"})
			return
		}
	}
	user, err := fetchDiscordUser(ctx, cfg, token)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "discord_user_failed"})
		return
	}
	if strings.TrimSpace(user.ID) == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "discord_user_missing"})
		return
	}

	displayName := strings.TrimSpace(user.GlobalName)
	if displayName == "" {
		displayName = strings.TrimSpace(user.Username)
	}
	if displayName == "" {
		displayName = "Discord Customer"
	}

	storeID := payload.StoreID
	if storeID == "" {
		if pending, err := consumeDiscordPendingSelection(ctx, cfg, firestoreClient, user.ID); err != nil {
			log.Printf("discord pending selection lookup failed user=%s err=%v", user.ID, err)
		} else if pending != nil {
			storeID = strings.TrimSpace(pending.StoreID)
			if pending.StartGroupOrder {
				payload.StartGroupOrder = true
			}
		}
	}
	storeMeta := storeMetadata{}
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

	session, err := buildDiscordSession(ctx, cfg, firestoreClient, storeID, storeMeta, user, displayName)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	botUsername := ""
	writeJSON(w, http.StatusOK, webAppSessionStartResponse{
		SessionID:    sessionDocID(session.Channel, session.AccountID, session.UserID),
		AccountID:    session.AccountID,
		UserID:       session.UserID,
		DisplayName:  session.DisplayName,
		StoreID:      session.StoreID,
		StoreName:    storeMeta.StoreName,
		TenantID:     session.TenantID,
		CustomerID:   session.CustomerID,
		BusinessType: session.BusinessType,
		StartGroup:   payload.StartGroupOrder && session.StoreID != "",
		BotUsername:  botUsername,
	})
}
