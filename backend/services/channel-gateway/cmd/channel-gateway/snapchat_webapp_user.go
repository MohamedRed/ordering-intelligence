package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type snapchatUserResponse struct {
	ExternalID  string
	DisplayName string
}

func fetchSnapchatUser(
	ctx context.Context,
	cfg *serviceConfig,
	accessToken string,
) (snapchatUserResponse, error) {
	endpoint := strings.TrimRight(cfg.SnapchatAPIBaseURL, "/") + "/v1/me"
	query := `{"query":"{me{externalId displayName}}"}`
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(query))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(accessToken))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return snapchatUserResponse{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return snapchatUserResponse{}, fmt.Errorf("snapchat user failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}

	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return snapchatUserResponse{}, err
	}
	data, _ := payload["data"].(map[string]any)
	me, _ := data["me"].(map[string]any)
	externalID := strings.TrimSpace(anyToString(me["externalId"]))
	displayName := strings.TrimSpace(anyToString(me["displayName"]))
	if externalID == "" {
		externalID = strings.TrimSpace(anyToString(me["external_id"]))
	}
	if displayName == "" {
		displayName = strings.TrimSpace(anyToString(me["display_name"]))
	}
	return snapchatUserResponse{
		ExternalID:  externalID,
		DisplayName: displayName,
	}, nil
}
