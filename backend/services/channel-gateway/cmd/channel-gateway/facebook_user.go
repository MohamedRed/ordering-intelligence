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

type facebookUserResponse struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func fetchFacebookUser(ctx context.Context, cfg *serviceConfig, accessToken string) (facebookUserResponse, error) {
	base := strings.TrimSpace(cfg.FacebookGraphBaseURL)
	if base == "" {
		base = "https://graph.facebook.com"
	}
	endpoint, _ := url.Parse(strings.TrimRight(base, "/") + "/me")
	query := endpoint.Query()
	query.Set("fields", "id,name")
	endpoint.RawQuery = query.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(accessToken))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return facebookUserResponse{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return facebookUserResponse{}, fmt.Errorf("facebook user failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var user facebookUserResponse
	if err := json.Unmarshal(body, &user); err != nil {
		return facebookUserResponse{}, err
	}
	return user, nil
}
