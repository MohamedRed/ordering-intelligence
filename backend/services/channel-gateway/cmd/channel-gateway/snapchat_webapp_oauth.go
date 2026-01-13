package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

type snapchatTokenResponse struct {
	AccessToken  string `json:"access_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	RefreshToken string `json:"refresh_token"`
	Scope        string `json:"scope"`
	IDToken      string `json:"id_token"`
}

var errSnapchatNotConfigured = errors.New("snapchat_not_configured")

func exchangeSnapchatOAuthToken(
	ctx context.Context,
	cfg *serviceConfig,
	code string,
	codeVerifier string,
	redirectURI string,
) (string, error) {
	if cfg.SnapchatClientID == "" {
		return "", errSnapchatNotConfigured
	}
	endpoint := strings.TrimRight(cfg.SnapchatAccountsBaseURL, "/") + "/accounts/oauth2/token"
	data := url.Values{}
	data.Set("client_id", cfg.SnapchatClientID)
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
	data.Set("code_verifier", codeVerifier)
	if strings.TrimSpace(redirectURI) != "" {
		data.Set("redirect_uri", strings.TrimSpace(redirectURI))
	}
	if strings.TrimSpace(cfg.SnapchatClientSecret) != "" {
		data.Set("client_secret", strings.TrimSpace(cfg.SnapchatClientSecret))
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
		return "", fmt.Errorf("snapchat token failed status=%d body=%s", resp.StatusCode, truncateForLog(body, 1000))
	}
	var tokenResp snapchatTokenResponse
	if err := json.Unmarshal(body, &tokenResp); err != nil {
		return "", err
	}
	token := strings.TrimSpace(tokenResp.AccessToken)
	if token == "" {
		return "", fmt.Errorf("snapchat token missing access_token")
	}
	return token, nil
}
