package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type discordInviteResponse struct {
	Code string `json:"code"`
}

func createDiscordActivityInvite(ctx context.Context, cfg *serviceConfig) (string, error) {
	channelID := strings.TrimSpace(cfg.DiscordActivityChannelID)
	if channelID == "" {
		return "", fmt.Errorf("missing activity channel id")
	}
	if strings.TrimSpace(cfg.DiscordClientID) == "" {
		return "", fmt.Errorf("missing discord client id")
	}
	token := strings.TrimSpace(cfg.DiscordBotToken)
	if token == "" {
		return "", fmt.Errorf("missing discord bot token")
	}
	apiBase := strings.TrimRight(strings.TrimSpace(cfg.DiscordAPIBase), "/")
	if apiBase == "" {
		apiBase = "https://discord.com/api/v10"
	}
	payload := map[string]any{
		"max_age":               3600,
		"max_uses":              0,
		"temporary":             false,
		"unique":                true,
		"target_type":           2,
		"target_application_id": cfg.DiscordClientID,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("%s/channels/%s/invites", apiBase, channelID), bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bot %s", token))

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	bodyBytes, readErr := io.ReadAll(resp.Body)
	bodyText := strings.TrimSpace(string(bodyBytes))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if readErr != nil {
			return "", fmt.Errorf("invite create failed status=%d body_read_error=%v", resp.StatusCode, readErr)
		}
		if bodyText == "" {
			return "", fmt.Errorf("invite create failed status=%d empty_body", resp.StatusCode)
		}
		return "", fmt.Errorf("invite create failed status=%d body=%s", resp.StatusCode, bodyText)
	}
	var invite discordInviteResponse
	if err := json.Unmarshal(bodyBytes, &invite); err != nil {
		return "", err
	}
	if strings.TrimSpace(invite.Code) == "" {
		return "", fmt.Errorf("invite code missing")
	}
	return fmt.Sprintf("https://discord.gg/%s", invite.Code), nil
}
