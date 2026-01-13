package main

import (
	"encoding/json"
	"net/http"
	"strings"
)

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func stringOrDefault(value interface{}, fallback string) string {
	switch v := value.(type) {
	case string:
		if strings.TrimSpace(v) == "" {
			return fallback
		}
		return v
	default:
		return fallback
	}
}

func normalizePhone(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return ""
	}
	var b strings.Builder
	for i := 0; i < len(p); i++ {
		ch := p[i]
		if ch >= '0' && ch <= '9' {
			b.WriteByte(ch)
			continue
		}
		if ch == '+' && b.Len() == 0 {
			b.WriteByte(ch)
		}
	}
	return b.String()
}

func normalizeChannel(value string) string {
	value = strings.TrimSpace(strings.ToLower(value))
	switch value {
	case "telegram_webapp", "telegram":
		return "telegram"
	case "discord_webapp", "discord":
		return "discord"
	case "snapchat_webapp", "snapchat":
		return "snapchat"
	default:
		return value
	}
}
