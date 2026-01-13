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

type facebookOAuthTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

func exchangeFacebookOAuthToken(ctx context.Context, cfg *serviceConfig, code, redirectURI string) (string, error) {
	clientID := strings.TrimSpace(cfg.FacebookAppID)
	clientSecret := strings.TrimSpace(cfg.FacebookAppSecret)
	if clientID == "" || clientSecret == "" {
		return "", errMobileOAuthNotConfigured
	}
	base := strings.TrimSpace(cfg.FacebookGraphBaseURL)
	if base == "" {
		base = "https://graph.facebook.com"
	}
	endpoint, _ := url.Parse(strings.TrimRight(base, "/") + "/oauth/access_token")
	query := endpoint.Query()
	query.Set("client_id", clientID)
	query.Set("client_secret", clientSecret)
	query.Set("code", strings.TrimSpace(code))
	if strings.TrimSpace(redirectURI) != "" {
		query.Set("redirect_uri", strings.TrimSpace(redirectURI))
	}
	endpoint.RawQuery = query.Encode()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("facebook token failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var tokenResp facebookOAuthTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	return strings.TrimSpace(tokenResp.AccessToken), nil
}
