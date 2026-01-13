package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

type fuelPumpPatch struct {
	PumpNumber string `json:"pumpNumber"`
}

type fuelCompleteRequest struct {
	FinalLiters      float64 `json:"finalLiters,omitempty"`
	FinalAmountCents int64   `json:"finalAmountCents,omitempty"`
}

func handleFuelPumpUpdate(
	ctx context.Context,
	client *cloudfirestore.Client,
	requireAuth bool,
	w http.ResponseWriter,
	r *http.Request,
	orderID string,
) {
	var payload fuelPumpPatch
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || strings.TrimSpace(payload.PumpNumber) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	updated, err := updateFuelPumpNumber(ctx, client, orderID, payload.PumpNumber, r.Context(), requireAuth)
	if err != nil {
		writeFuelUpdateError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func handleFuelComplete(
	ctx context.Context,
	client *cloudfirestore.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
	orderID string,
) {
	var payload fuelCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	updated, err := completeFuelOrder(ctx, client, cfg, orderID, payload, r.Context())
	if err != nil {
		writeFuelUpdateError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func writeFuelUpdateError(w http.ResponseWriter, err error) {
	switch err {
	case errOrderNotFound:
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
	case errUnauthorizedStore:
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	case errInvalidTransition:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_status_transition"})
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
	}
}
