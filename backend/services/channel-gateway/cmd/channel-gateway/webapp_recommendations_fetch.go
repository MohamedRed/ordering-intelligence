package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	"golang.org/x/oauth2"
	"google.golang.org/api/idtoken"
)

func loadSessionByID(ctx context.Context, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
	doc, err := client.Collection(channelSessionsCollection).Doc(sessionID).Get(ctx)
	if err != nil {
		return channelSession{}, err
	}
	var session channelSession
	if err := doc.DataTo(&session); err != nil {
		return channelSession{}, err
	}
	return session, nil
}

func fetchTopReorders(ctx context.Context, baseURL, tenantID, customerID, storeID string) ([]reorderTemplate, error) {
	base := strings.TrimSpace(baseURL)
	if base == "" {
		return []reorderTemplate{}, nil
	}
	tokenSource, err := idtoken.NewTokenSource(ctx, base)
	if err != nil {
		return nil, err
	}
	client := oauth2.NewClient(ctx, tokenSource)
	query := fmt.Sprintf("customerId=%s&storeId=%s", urlQueryEscape(customerID), urlQueryEscape(storeID))
	if strings.TrimSpace(tenantID) != "" {
		query = fmt.Sprintf("tenantId=%s&%s", urlQueryEscape(tenantID), query)
	}
	url := fmt.Sprintf("%s/v1/reorders/top?%s", strings.TrimRight(base, "/"), query)
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return []reorderTemplate{}, nil
	}
	var out struct {
		TopReorders []reorderTemplate `json:"topReorders"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return out.TopReorders, nil
}

func limitFromQuery(r *http.Request, fallback int) int {
	limit := fallback
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			limit = parsed
		}
	}
	if limit <= 0 {
		return fallback
	}
	if limit > 5 {
		return 5
	}
	return limit
}
