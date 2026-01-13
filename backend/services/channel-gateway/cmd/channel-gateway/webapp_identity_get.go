package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleWebAppIdentity(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 4*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
		return
	}

	profile, err := fetchCustomerProfile(ctx, cfg.CustomerProfileServiceURL, session.CustomerID)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "customer_profile_unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, profile)
}
