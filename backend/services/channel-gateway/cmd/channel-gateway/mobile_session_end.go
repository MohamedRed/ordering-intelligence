package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type mobileSessionEndRequest struct {
	SessionID string `json:"sessionId"`
	Signature string `json:"signature"`
	Timestamp string `json:"timestamp"`
}

func handleMobileSessionEnd(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload mobileSessionEndRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.Signature = strings.TrimSpace(payload.Signature)
	payload.Timestamp = strings.TrimSpace(payload.Timestamp)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_id"})
		return
	}

	auth, err := extractMobileAuthParts(payload.Signature, payload.Timestamp)
	if err == nil {
		if err := verifyMobileSessionIDAuth(cfg, payload.SessionID, auth); err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_invalid"})
			return
		}
	} else if err == errMobileAuthMissing {
		if strings.TrimSpace(cfg.MobileSessionSecret) != "" {
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

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	_, err = firestoreClient.Collection(channelSessionsCollection).Doc(payload.SessionID).Delete(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_delete_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
