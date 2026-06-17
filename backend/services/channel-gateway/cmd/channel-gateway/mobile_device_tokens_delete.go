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

type mobileDeviceTokenDeleteRequest struct {
	SessionID   string `json:"sessionId"`
	DeviceToken string `json:"deviceToken"`
	Signature   string `json:"signature,omitempty"`
	Timestamp   string `json:"timestamp,omitempty"`
}

func handleMobileDeviceTokenDelete(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload mobileDeviceTokenDeleteRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.DeviceToken = strings.TrimSpace(payload.DeviceToken)
	if payload.SessionID == "" || payload.DeviceToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
		return
	}
	if !verifyMobileSessionRequestAuth(cfg, w, r, payload.SessionID, payload.Signature, payload.Timestamp) {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
		return
	}

	doc := firestoreClient.Collection("deviceTokens").Doc(payload.DeviceToken)
	snapshot, err := doc.Get(ctx)
	if err == nil {
		data := snapshot.Data()
		docCustomer, _ := data["customerId"].(string)
		docUser, _ := data["userId"].(string)
		docCustomer = strings.TrimSpace(docCustomer)
		docUser = strings.TrimSpace(docUser)
		if docCustomer != "" && docCustomer != customerID && docUser != customerID {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "token_not_owned"})
			return
		}
	} else if status.Code(err) != codes.NotFound {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "device_token_lookup_failed"})
		return
	}

	if _, err := doc.Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "device_token_delete_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
