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

type tiktokOAuthTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
	Scope       string `json:"scope"`
	OpenID      string `json:"open_id"`
}

func exchangeTikTokOAuthToken(ctx context.Context, cfg *serviceConfig, code, verifier, redirectURI string) (string, error) {
	clientKey := strings.TrimSpace(cfg.TikTokClientKey)
	clientSecret := strings.TrimSpace(cfg.TikTokClientSecret)
	if clientKey == "" || clientSecret == "" {
		return "", errMobileOAuthNotConfigured
	}
	base := strings.TrimSpace(cfg.TikTokAPIBaseURL)
	if base == "" {
		base = "https://open.tiktokapis.com"
	}
	endpoint := strings.TrimRight(base, "/") + "/v2/oauth/token/"
	data := url.Values{}
	data.Set("client_key", clientKey)
	data.Set("client_secret", clientSecret)
	data.Set("grant_type", "authorization_code")
	data.Set("code", strings.TrimSpace(code))
	if strings.TrimSpace(verifier) != "" {
		data.Set("code_verifier", strings.TrimSpace(verifier))
	}
	if strings.TrimSpace(redirectURI) != "" {
		data.Set("redirect_uri", strings.TrimSpace(redirectURI))
	}

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(data.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("tiktok token failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var tokenResp tiktokOAuthTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	return strings.TrimSpace(tokenResp.AccessToken), nil
}
