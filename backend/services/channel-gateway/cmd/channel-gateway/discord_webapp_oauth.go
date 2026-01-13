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

func exchangeDiscordOAuthToken(ctx context.Context, cfg *serviceConfig, code, redirectURI string) (string, error) {
	if cfg.DiscordClientID == "" || cfg.DiscordClientSecret == "" {
		return "", errDiscordNotConfigured
	}
	endpoint := strings.TrimRight(cfg.DiscordAPIBase, "/") + "/oauth2/token"
	data := url.Values{}
	data.Set("client_id", cfg.DiscordClientID)
	data.Set("client_secret", cfg.DiscordClientSecret)
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
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
		return "", fmt.Errorf("discord token failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var tokenResp discordOAuthTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	return strings.TrimSpace(tokenResp.AccessToken), nil
}

func fetchDiscordUser(ctx context.Context, cfg *serviceConfig, accessToken string) (discordUserResponse, error) {
	endpoint := strings.TrimRight(cfg.DiscordAPIBase, "/") + "/users/@me"
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(accessToken))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return discordUserResponse{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return discordUserResponse{}, fmt.Errorf("discord user failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var user discordUserResponse
	if err := json.Unmarshal(body, &user); err != nil {
		return discordUserResponse{}, err
	}
	return user, nil
}
