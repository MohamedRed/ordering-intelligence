package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

type tiktokUserResponse struct {
	OpenID      string `json:"open_id"`
	UnionID     string `json:"union_id"`
	DisplayName string `json:"display_name"`
}

type tiktokUserEnvelope struct {
	Data struct {
		User tiktokUserResponse `json:"user"`
	} `json:"data"`
}

func fetchTikTokUser(ctx context.Context, cfg *serviceConfig, accessToken string) (tiktokUserResponse, error) {
	base := strings.TrimSpace(cfg.TikTokAPIBaseURL)
	if base == "" {
		base = "https://open.tiktokapis.com"
	}
	endpoint, _ := url.Parse(strings.TrimRight(base, "/") + "/v2/user/info/")
	query := endpoint.Query()
	query.Set("fields", "open_id,union_id,display_name")
	endpoint.RawQuery = query.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(accessToken))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return tiktokUserResponse{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return tiktokUserResponse{}, fmt.Errorf("tiktok user failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var env tiktokUserEnvelope
	if err := json.Unmarshal(body, &env); err != nil {
		return tiktokUserResponse{}, err
	}
	return env.Data.User, nil
}
