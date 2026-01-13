package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleMobileSessionStart(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload mobileSessionStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	provider := normalizeMobileProvider(payload.Provider)
	subject := strings.TrimSpace(payload.ProviderUserID)
	displayName := strings.TrimSpace(payload.DisplayName)
	accessToken := strings.TrimSpace(payload.AccessToken)
	authCode := strings.TrimSpace(payload.AuthCode)
	codeVerifier := strings.TrimSpace(payload.CodeVerifier)
	redirectURI := strings.TrimSpace(payload.RedirectURI)
	if provider == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_provider_identity"})
		return
	}
	if !isAllowedMobileProvider(provider) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_provider"})
		return
	}

	auth, err := extractMobileAuth(r, payload)
	secretConfigured := strings.TrimSpace(cfg.MobileSessionSecret) != ""
	if err == nil {
		if err := verifyMobileSessionAuth(cfg, provider, subject, auth); err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_invalid"})
			return
		}
	} else if err == errMobileAuthMissing {
		if secretConfigured {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_missing"})
			return
		}
		if strings.ToLower(strings.TrimSpace(cfg.Environment)) == "production" {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_not_configured"})
			return
		}
	} else {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_invalid"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	if accessToken == "" && authCode != "" && provider != "telegram" {
		if token, err := exchangeMobileOAuthToken(ctx, cfg, provider, authCode, codeVerifier, redirectURI); err == nil {
			accessToken = token
		} else {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "provider_token_exchange_failed"})
			return
		}
	}

	if provider != "telegram" {
		if accessToken == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "provider_token_missing"})
			return
		}
		profile, err := verifyMobileProvider(ctx, cfg, provider, accessToken)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "provider_verify_failed"})
			return
		}
		if profile.Subject != "" {
			if subject != "" && subject != profile.Subject {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "provider_subject_mismatch"})
				return
			}
			subject = profile.Subject
		}
		if displayName == "" {
			displayName = profile.DisplayName
		}
	}
	if subject == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_provider_identity"})
		return
	}

	storeID := strings.TrimSpace(payload.StoreID)
	storeMeta := storeMetadata{}
	if storeID != "" {
		meta, err := fetchStoreMetadata(ctx, firestoreClient, storeID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_lookup_failed"})
			return
		}
		storeMeta = meta
		storeID = storeMeta.StoreID
	}

	clientPlatform := normalizeMobilePlatform(payload.ClientPlatform)
	clientApp := strings.TrimSpace(payload.ClientApp)
	if clientApp == "" {
		clientApp = "consumer-mobile"
	}
	clientVersion := strings.TrimSpace(payload.ClientVersion)
	customerID := ""
	if resolved, err := resolveCustomerID(ctx, cfg, provider, subject, displayName, storeMeta.TenantID, customerResolveContext{
		StoreID:  storeID,
		Platform: clientPlatform,
		Provider: provider,
	}); err == nil {
		customerID = resolved
	}
	var fuelPreauthCap int64
	if customerID != "" {
		if profile, err := fetchCustomerProfile(ctx, cfg.CustomerProfileServiceURL, customerID); err == nil {
			fuelPreauthCap = profile.FuelPreauthCapCents
		}
	}
	userID := subject
	if customerID != "" {
		userID = customerID
	}

	session := channelSession{
		Channel:                  "mobile",
		AccountID:                "mobile_app",
		UserID:                   userID,
		DisplayName:              displayName,
		TenantID:                 storeMeta.TenantID,
		CustomerID:               customerID,
		StoreID:                  storeID,
		BusinessType:             storeMeta.BusinessType,
		AuthProvider:             provider,
		ClientPlatform:           clientPlatform,
		ClientApp:                clientApp,
		ClientVersion:            clientVersion,
		ElevenLabsConversationID: "",
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                time.Now().UTC(),
	}

	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	writeJSON(w, http.StatusOK, mobileSessionStartResponse{
		SessionID:              sessionDocID(session.Channel, session.AccountID, session.UserID),
		AccountID:              session.AccountID,
		UserID:                 session.UserID,
		DisplayName:            session.DisplayName,
		StoreID:                session.StoreID,
		StoreName:              storeMeta.StoreName,
		TenantID:               session.TenantID,
		CustomerID:             session.CustomerID,
		BusinessType:           session.BusinessType,
		Currency:               storeMeta.Currency,
		FuelDefaultPrepayCents: storeMeta.FuelDefaultPrepayCents,
		FuelPreauthCapCents:    fuelPreauthCap,
	})
}
