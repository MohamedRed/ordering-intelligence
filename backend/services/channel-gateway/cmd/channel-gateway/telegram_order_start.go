package main

import "strings"

func parseTelegramOrderStart(text string) string {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return ""
	}
	parts := strings.Fields(trimmed)
	if len(parts) == 0 {
		return ""
	}
	candidate := parts[0]
	if strings.HasPrefix(candidate, "/start") {
		if len(parts) < 2 {
			return ""
		}
		candidate = parts[1]
	}
	return extractTelegramOrderToken(candidate)
}

func extractTelegramOrderToken(token string) string {
	raw := strings.TrimSpace(token)
	if raw == "" {
		return ""
	}
	lower := strings.ToLower(raw)
	for _, prefix := range []string{"order_", "order:", "order-"} {
		if strings.HasPrefix(lower, prefix) {
			return strings.TrimSpace(raw[len(prefix):])
		}
	}
	return ""
}
