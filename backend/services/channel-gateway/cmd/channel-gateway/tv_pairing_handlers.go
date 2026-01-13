package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleTvPairStart(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	var payload tvPairingStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	baseURL := resolveRequestBaseURL(r)
	record, response, err := createTvPairing(ctx, client, payload, baseURL)
	if err != nil || record.PairingID == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "pairing_create_failed"})
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func handleTvPairLanding(w http.ResponseWriter, r *http.Request) {
	code := strings.TrimSpace(r.URL.Query().Get("code"))
	pairingID := strings.TrimSpace(r.URL.Query().Get("pairingId"))
	appScheme := "com.orderingintelligence.consumer"
	deepLink := ""
	if code != "" || pairingID != "" {
		deepLink = fmt.Sprintf("%s://tv-pair?code=%s&pairingId=%s",
			appScheme,
			url.QueryEscape(code),
			url.QueryEscape(pairingID),
		)
	}
	html := buildTvPairingLandingHTML(code, pairingID, deepLink)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(html))
}

func handleTvPairState(
	w http.ResponseWriter,
	r *http.Request,
	client *cloudfirestore.Client,
) {
	pairingID := strings.TrimSpace(r.URL.Query().Get("pairingId"))
	code := strings.TrimSpace(r.URL.Query().Get("code"))
	if pairingID == "" && code == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_pairing"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	record, err := resolveTvPairing(ctx, client, pairingID, code)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "pairing_not_found"})
		return
	}
	now := time.Now().UTC()
	if record.Status == tvPairingStatusPending && now.After(record.ExpiresAt) {
		record.Status = tvPairingStatusExpired
		_ = upsertTvPairing(ctx, client, record)
	}

	response := tvPairingStateResponse{
		Status:    record.Status,
		PairingID: record.PairingID,
		Code:      record.Code,
		ExpiresAt: record.ExpiresAt.Format(time.RFC3339),
	}
	if record.Status == tvPairingStatusLinked {
		response.SessionID = record.SessionID
		response.SessionToken = record.SessionToken
		response.CustomerID = record.CustomerID
		response.DisplayName = record.DisplayName
		if !record.LinkedAt.IsZero() {
			response.LinkedAt = record.LinkedAt.UTC().Format(time.RFC3339)
		}
		response.Linked = true
		response.Session = record.SessionToken
	}
	writeJSON(w, http.StatusOK, response)
}

func handleTvPairComplete(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	var payload tvPairingCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	pairingID := strings.TrimSpace(payload.PairingID)
	code := strings.TrimSpace(payload.Code)
	sessionID := strings.TrimSpace(payload.SessionID)
	if pairingID == "" && code == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_pairing"})
		return
	}
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	record, err := resolveTvPairing(ctx, client, pairingID, code)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "pairing_not_found"})
		return
	}
	now := time.Now().UTC()
	if record.Status == tvPairingStatusLinked {
		writeJSON(w, http.StatusOK, buildTvPairingStateResponse(record))
		return
	}
	if now.After(record.ExpiresAt) {
		record.Status = tvPairingStatusExpired
		_ = upsertTvPairing(ctx, client, record)
		writeJSON(w, http.StatusGone, map[string]string{"error": "pairing_expired"})
		return
	}

	session, err := loadSessionByID(ctx, client, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}

	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		if resolved, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, session.TenantID, customerResolveContext{
			StoreID:  session.StoreID,
			Platform: session.ClientPlatform,
			Provider: session.AuthProvider,
		}); err == nil {
			customerID = strings.TrimSpace(resolved)
		}
	}
	userID := customerID
	if userID == "" {
		userID = strings.TrimSpace(session.UserID)
	}
	if userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_user"})
		return
	}

	tvSession := channelSession{
		Channel:        "tv",
		AccountID:      "tv_app",
		UserID:         userID,
		DisplayName:    session.DisplayName,
		TenantID:       session.TenantID,
		CustomerID:     customerID,
		StoreID:        session.StoreID,
		BusinessType:   session.BusinessType,
		AuthProvider:   session.AuthProvider,
		ClientPlatform: "tv",
		ClientApp:      "consumer-tv",
		ClientVersion:  record.ClientVersion,
		LastSeenAt:     now,
		CreatedAt:      now,
	}
	if err := upsertSession(ctx, client, tvSession); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_write_failed"})
		return
	}

	token, err := generateSessionToken()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_token_failed"})
		return
	}
	tvSessionID := sessionDocID(tvSession.Channel, tvSession.AccountID, tvSession.UserID)
	sessionRecord := tvSessionRecord{
		SessionToken: token,
		SessionID:    tvSessionID,
		CustomerID:   customerID,
		DeviceID:     record.DeviceID,
		DeviceType:   record.DeviceType,
		CreatedAt:    now,
		ExpiresAt:    now.Add(tvSessionTTL),
		LastSeenAt:   now,
	}
	if err := upsertTvSession(ctx, client, sessionRecord); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_store_failed"})
		return
	}

	record.Status = tvPairingStatusLinked
	record.SessionID = tvSessionID
	record.SessionToken = token
	record.CustomerID = customerID
	record.DisplayName = session.DisplayName
	record.LinkedAt = now
	if payload.DeviceName != "" {
		record.DeviceName = strings.TrimSpace(payload.DeviceName)
	}
	if err := upsertTvPairing(ctx, client, record); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "pairing_update_failed"})
		return
	}

	writeJSON(w, http.StatusOK, buildTvPairingStateResponse(record))
}

func handleTvSessionGet(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	token := tvSessionTokenFromRequest(r)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_token"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	record, err := fetchTvSessionByToken(ctx, client, token)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if time.Now().UTC().After(record.ExpiresAt) {
		_ = deleteTvSession(ctx, client, token)
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "session_expired"})
		return
	}
	session, err := loadSessionWithCustomer(ctx, cfg, client, record.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	record.LastSeenAt = time.Now().UTC()
	_ = upsertTvSession(ctx, client, record)

	storeMeta := storeMetadata{}
	if session.StoreID != "" {
		if meta, err := fetchStoreMetadata(ctx, client, session.StoreID); err == nil {
			storeMeta = meta
		}
	}
	var fuelPreauthCap int64
	if session.CustomerID != "" {
		if profile, err := fetchCustomerProfile(ctx, cfg.CustomerProfileServiceURL, session.CustomerID); err == nil {
			fuelPreauthCap = profile.FuelPreauthCapCents
		}
	}

	writeJSON(w, http.StatusOK, tvSessionResponse{
		SessionID:              record.SessionID,
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

func handleTvSessionEnd(
	w http.ResponseWriter,
	r *http.Request,
	client *cloudfirestore.Client,
) {
	token := tvSessionTokenFromRequest(r)
	if token == "" {
		var payload struct {
			SessionToken string `json:"sessionToken"`
		}
		_ = json.NewDecoder(r.Body).Decode(&payload)
		token = strings.TrimSpace(payload.SessionToken)
	}
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_token"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	_ = deleteTvSession(ctx, client, token)
	w.WriteHeader(http.StatusNoContent)
}

func handleTvReorders(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	token := tvSessionTokenFromRequest(r)
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_token"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	record, err := fetchTvSessionByToken(ctx, client, token)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "session_not_found"})
		return
	}
	session, err := loadSessionWithCustomer(ctx, cfg, client, record.SessionID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "session_not_found"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusOK, map[string]any{"items": []tvReorderItem{}})
		return
	}
	reorderDocs, err := fetchReorderDocsByCustomerID(ctx, client, customerID)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"items": []tvReorderItem{}})
		return
	}
	storeCache := map[string]storeMetadata{}
	items := []tvReorderItem{}
	for _, rd := range reorderDocs {
		meta, ok := storeCache[rd.StoreID]
		if !ok {
			meta, _ = fetchStoreMetadata(ctx, client, rd.StoreID)
			storeCache[rd.StoreID] = meta
		}
		for _, t := range rd.TopReorders {
			web := toWebAppReorder(t, meta)
			items = append(items, tvReorderItem{
				Title:           tvReorderTitle(web),
				Subtitle:        tvReorderSubtitle(web),
				StoreID:         web.StoreID,
				StoreName:       web.StoreName,
				Currency:        web.Currency,
				ItemCount:       web.ItemCount,
				OrderTemplateID: t.OrderTemplateID,
				Items:           web.Items,
				Fuel:            web.Fuel,
			})
		}
	}
	limit := limitFromQuery(r, 5)
	if len(items) > limit {
		items = items[:limit]
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func resolveTvPairing(
	ctx context.Context,
	client *cloudfirestore.Client,
	pairingID string,
	code string,
) (tvPairingRecord, error) {
	if pairingID != "" {
		return fetchTvPairingByID(ctx, client, pairingID)
	}
	return fetchTvPairingByCode(ctx, client, code)
}

func buildTvPairingStateResponse(record tvPairingRecord) tvPairingStateResponse {
	response := tvPairingStateResponse{
		Status:    record.Status,
		PairingID: record.PairingID,
		Code:      record.Code,
		ExpiresAt: record.ExpiresAt.Format(time.RFC3339),
	}
	if record.Status == tvPairingStatusLinked {
		response.SessionID = record.SessionID
		response.SessionToken = record.SessionToken
		response.CustomerID = record.CustomerID
		response.DisplayName = record.DisplayName
		if !record.LinkedAt.IsZero() {
			response.LinkedAt = record.LinkedAt.UTC().Format(time.RFC3339)
		}
		response.Linked = true
		response.Session = record.SessionToken
	}
	return response
}

type tvReorderItem struct {
	Title           string        `json:"title"`
	Subtitle        string        `json:"subtitle"`
	StoreID         string        `json:"storeId"`
	StoreName       string        `json:"storeName"`
	Currency        string        `json:"currency,omitempty"`
	ItemCount       int           `json:"itemCount"`
	OrderTemplateID string        `json:"orderTemplateId,omitempty"`
	Items           []reorderItem `json:"items,omitempty"`
	Fuel            *reorderFuel  `json:"fuel,omitempty"`
}

func tvReorderTitle(item webAppReorder) string {
	title := strings.TrimSpace(item.Title)
	if title != "" {
		return title
	}
	if item.StoreName != "" {
		return fmt.Sprintf("Reorder from %s", item.StoreName)
	}
	return "Reorder"
}

func tvReorderSubtitle(item webAppReorder) string {
	if item.Fuel != nil {
		amount := ""
		if item.Fuel.RequestedAmountCents > 0 {
			amount = formatCurrency(item.Fuel.RequestedAmountCents, item.Currency)
		}
		if amount != "" {
			return fmt.Sprintf("Fuel · %s", amount)
		}
		return "Fuel"
	}
	if item.StoreName == "" {
		return fmt.Sprintf("%d items", item.ItemCount)
	}
	return fmt.Sprintf("%s · %d items", item.StoreName, item.ItemCount)
}

func formatCurrency(amountCents int64, currency string) string {
	if amountCents <= 0 {
		return ""
	}
	value := float64(amountCents) / 100
	code := strings.ToUpper(strings.TrimSpace(currency))
	if code == "" {
		return fmt.Sprintf("$%.2f", value)
	}
	return fmt.Sprintf("%s %.2f", code, value)
}

func tvSessionTokenFromRequest(r *http.Request) string {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if strings.HasPrefix(strings.ToLower(auth), "bearer ") {
		return strings.TrimSpace(auth[7:])
	}
	if token := strings.TrimSpace(r.URL.Query().Get("sessionToken")); token != "" {
		return token
	}
	if token := strings.TrimSpace(r.URL.Query().Get("token")); token != "" {
		return token
	}
	return ""
}

func resolveRequestBaseURL(r *http.Request) string {
	scheme := strings.TrimSpace(r.Header.Get("X-Forwarded-Proto"))
	if scheme == "" {
		if r.TLS != nil {
			scheme = "https"
		} else if r.URL.Scheme != "" {
			scheme = r.URL.Scheme
		} else {
			scheme = "http"
		}
	}
	host := strings.TrimSpace(r.Header.Get("X-Forwarded-Host"))
	if host == "" {
		host = strings.TrimSpace(r.Host)
	}
	if host == "" {
		return ""
	}
	return fmt.Sprintf("%s://%s", scheme, host)
}

func buildTvPairingLandingHTML(code, pairingID, deepLink string) string {
	label := "Open the Ordering Intelligence app and enter this code."
	button := ""
	if deepLink != "" {
		button = fmt.Sprintf(
			`<p><a class="cta" href="%s">Open app to link</a></p>`,
			deepLink,
		)
	}
	codeBlock := `<span class="code">----</span>`
	if code != "" {
		codeBlock = fmt.Sprintf(`<span class="code">%s</span>`, code)
	}
	if pairingID != "" {
		label = fmt.Sprintf("%s Pairing ID: %s", label, pairingID)
	}
	return fmt.Sprintf(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Link your TV</title>
    <style>
      body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#0f0f0f;color:#fff;margin:0;padding:40px;}
      .card{max-width:520px;margin:0 auto;background:#1b1b1b;border-radius:16px;padding:32px;box-shadow:0 20px 40px rgba(0,0,0,.4);}
      .code{font-size:36px;letter-spacing:6px;font-weight:700;color:#e4002b;}
      .cta{display:inline-block;margin-top:20px;background:#e4002b;color:#fff;padding:12px 18px;border-radius:10px;text-decoration:none;}
      .muted{color:#b0b0b0;margin-top:12px;}
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Link your TV</h1>
      <p>%s</p>
      <div>%s</div>
      %s
      <p class="muted">Keep this page open while linking.</p>
    </div>
  </body>
</html>`, label, codeBlock, button)
}
