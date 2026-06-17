package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
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
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	pumpNumber := strings.TrimSpace(payload.PumpNumber)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	if pumpNumber == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_pump_number"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomerFn(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_read_failed"})
		return
	}
	if _, err := authorizeSessionOrder(ctx, cfg, orderHTTPClient, session, orderID); err != nil {
		writeWebAppOrderAccessError(w, err)
		return
	}

	respBody, status, err := updateOrderFuelPump(ctx, cfg, orderHTTPClient, orderID, pumpNumber)
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
	endpoint := fmt.Sprintf("%s/orders/%s/fuel", strings.TrimRight(cfg.OrderServiceURL, "/"), url.PathEscape(strings.TrimSpace(orderID)))
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
