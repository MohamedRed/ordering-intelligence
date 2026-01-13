package main

import (
	"fmt"
	"net/url"
	"strings"
)

func buildTelegramInlineURL(baseURL, botUsername, storeID string, startGroup bool) string {
	if botUsername != "" {
		return buildTelegramStartAppURL(botUsername, storeID, startGroup)
	}
	return buildTelegramWebAppURL(baseURL, storeID, startGroup)
}

func buildTelegramStartAppURL(botUsername, storeID string, startGroup bool) string {
	username := cleanTelegramUsername(botUsername)
	if username == "" {
		return ""
	}
	base := fmt.Sprintf("https://t.me/%s", username)
	if strings.TrimSpace(storeID) == "" {
		return base
	}
	params := url.Values{}
	params.Set("startapp", buildStartAppParam(storeID, startGroup))
	return fmt.Sprintf("%s?%s", base, params.Encode())
}

func buildStartAppParam(storeID string, startGroup bool) string {
	value := strings.TrimSpace(storeID)
	if value == "" {
		return ""
	}
	if startGroup {
		return "g_" + value
	}
	return "s_" + value
}
