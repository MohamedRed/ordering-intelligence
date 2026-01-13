package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppFuelPreauthCapRequest struct {
	SessionID            string `json:"sessionId"`
	FuelPreauthCapCents  int64  `json:"fuelPreauthCapCents"`
}

func handleWebAppFuelPreauthCap(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	if strings.TrimSpace(cfg.CustomerProfileServiceURL) == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "customer_profile_not_configured"})
		return
	}
	var payload webAppFuelPreauthCapRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if payload.FuelPreauthCapCents < 0 {
		payload.FuelPreauthCapCents = 0
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_customer"})
		return
	}

	profile, err := updateCustomerFuelPreauthCap(
		ctx,
		cfg.CustomerProfileServiceURL,
		session.CustomerID,
		payload.FuelPreauthCapCents,
	)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "customer_profile_unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, profile)
}
