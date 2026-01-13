package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type snapchatWebAppSessionStartRequest struct {
	Code            string `json:"code"`
	CodeVerifier    string `json:"codeVerifier"`
	RedirectURI     string `json:"redirectUri"`
	StoreID         string `json:"storeId"`
	Locale          string `json:"locale"`
	StartGroupOrder bool   `json:"startGroupOrder"`
}

func handleSnapchatWebAppSessionStart(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload snapchatWebAppSessionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.Code = strings.TrimSpace(payload.Code)
	payload.CodeVerifier = strings.TrimSpace(payload.CodeVerifier)
	payload.RedirectURI = strings.TrimSpace(payload.RedirectURI)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.Locale = strings.TrimSpace(payload.Locale)
	if payload.Code == "" || payload.CodeVerifier == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_code"})
		return
	}
	if cfg.SnapchatClientID == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "snapchat_not_configured"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()

	token, err := exchangeSnapchatOAuthToken(ctx, cfg, payload.Code, payload.CodeVerifier, payload.RedirectURI)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "snapchat_oauth_failed"})
		return
	}
	user, err := fetchSnapchatUser(ctx, cfg, token)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "snapchat_user_failed"})
		return
	}
	if strings.TrimSpace(user.ExternalID) == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "snapchat_user_missing"})
		return
	}

	storeID := payload.StoreID
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

	session, err := buildSnapchatSession(ctx, cfg, firestoreClient, storeID, storeMeta, user)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	botUsername := strings.TrimSpace(resolveTelegramBotUsername(ctx, cfg))
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
