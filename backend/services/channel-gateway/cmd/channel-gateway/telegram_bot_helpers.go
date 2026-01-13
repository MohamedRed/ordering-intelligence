package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

var (
	telegramBotUsernameOnce sync.Once
	telegramBotUsername     string
)

func resolveTelegramBotUsername(ctx context.Context, cfg *serviceConfig) string {
	if cfg == nil {
		return ""
	}
	if strings.TrimSpace(cfg.TelegramBotUsername) != "" {
		return cleanTelegramUsername(cfg.TelegramBotUsername)
	}
	if strings.TrimSpace(cfg.TelegramBotToken) == "" {
		return ""
	}
	telegramBotUsernameOnce.Do(func() {
		username, err := fetchTelegramBotUsername(ctx, cfg.TelegramBotToken)
		if err == nil {
			telegramBotUsername = username
		}
	})
	return cleanTelegramUsername(telegramBotUsername)
}

func fetchTelegramBotUsername(ctx context.Context, token string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		fmt.Sprintf("https://api.telegram.org/bot%s/getMe", token), nil)
	if err != nil {
		return "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var payload struct {
		OK     bool `json:"ok"`
		Result struct {
			Username string `json:"username"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", err
	}
	if !payload.OK {
		return "", fmt.Errorf("telegram getMe failed")
	}
	return cleanTelegramUsername(payload.Result.Username), nil
}

func cleanTelegramUsername(username string) string {
	return strings.TrimPrefix(strings.TrimSpace(username), "@")
}
