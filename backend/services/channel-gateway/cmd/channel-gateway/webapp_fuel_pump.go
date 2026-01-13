package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppFuelPumpRequest struct {
	SessionID  string `json:"sessionId"`
	PumpNumber string `json:"pumpNumber"`
}

func handleWebAppFuelPumpUpdate(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	orderHTTPClient *http.Client,
	orderID string,
) {
	var payload webAppFuelPumpRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	pumpNumber := strings.TrimSpace(payload.PumpNumber)
	if pumpNumber == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_pump_number"})
		return
	}
	if strings.TrimSpace(payload.SessionID) != "" {
		if _, err := loadSessionByID(r.Context(), firestoreClient, payload.SessionID); err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
	}

	respBody, status, err := updateOrderFuelPump(r.Context(), cfg, orderHTTPClient, orderID, pumpNumber)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "order_service_unavailable"})
		return
	}
	if status < 200 || status >= 300 {
		writeJSON(w, status, map[string]any{"error": "fuel_update_failed", "details": string(respBody)})
		return
	}
	var parsed map[string]any
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_parse_failed"})
		return
	}
	writeJSON(w, http.StatusOK, parsed)
}

func updateOrderFuelPump(
	ctx context.Context,
	cfg *serviceConfig,
	client *http.Client,
	orderID string,
	pumpNumber string,
) ([]byte, int, error) {
	body, _ := json.Marshal(map[string]string{"pumpNumber": pumpNumber})
	endpoint := fmt.Sprintf("%s/orders/%s/fuel", strings.TrimRight(cfg.OrderServiceURL, "/"), orderID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPatch, endpoint, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	return respBody, resp.StatusCode, nil
}
