package agentcontext

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"google.golang.org/api/idtoken"
)

func resolveCustomerID(ctx context.Context, baseURL, tenantID, channel, userID, displayName string) string {
	base := strings.TrimSpace(baseURL)
	tenantID = strings.TrimSpace(tenantID)
	channel = strings.TrimSpace(channel)
	userID = strings.TrimSpace(userID)
	if base == "" || channel == "" || userID == "" {
		return ""
	}
	cctx, cancel := context.WithTimeout(ctx, 900*time.Millisecond)
	defer cancel()
	client, err := idtoken.NewClient(cctx, base)
	if err != nil {
		return ""
	}
	payload := map[string]any{
		"channel":     channel,
		"userId":      userID,
		"displayName": strings.TrimSpace(displayName),
		"allowCreate": true,
	}
	if tenantID != "" {
		payload["tenantId"] = tenantID
	}
	body, _ := json.Marshal(payload)
	url := fmt.Sprintf("%s/v1/customers/resolve", strings.TrimRight(base, "/"))
	req, _ := http.NewRequestWithContext(cctx, http.MethodPost, url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return ""
	}
	var out struct {
		CustomerID string `json:"customerId"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return ""
	}
	return strings.TrimSpace(out.CustomerID)
}

func fetchTopReorders(ctx context.Context, baseURL, tenantID, customerID, storeID string) any {
	base := strings.TrimSpace(baseURL)
	if base == "" || strings.TrimSpace(customerID) == "" {
		return nil
	}
	cctx, cancel := context.WithTimeout(ctx, 900*time.Millisecond)
	defer cancel()
	client, err := idtoken.NewClient(cctx, base)
	if err != nil {
		return nil
	}
	query := fmt.Sprintf("customerId=%s&storeId=%s", urlQueryEscape(customerID), urlQueryEscape(storeID))
	if strings.TrimSpace(tenantID) != "" {
		query = fmt.Sprintf("tenantId=%s&%s", urlQueryEscape(tenantID), query)
	}
	url := fmt.Sprintf("%s/v1/reorders/top?%s", strings.TrimRight(base, "/"), query)
	req, _ := http.NewRequestWithContext(cctx, http.MethodGet, url, nil)
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	var out struct {
		TopReorders any `json:"topReorders"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil
	}
	return out.TopReorders
}
