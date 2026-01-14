package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
)

func decodeWebAppChatTurnRequest(r *http.Request) (webappChatTurnRequest, int, string) {
	var payload webappChatTurnRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		return payload, http.StatusBadRequest, "invalid_payload"
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.Text = strings.TrimSpace(payload.Text)
	payload.AudioBase64 = strings.TrimSpace(payload.AudioBase64)
	payload.AudioMime = strings.TrimSpace(payload.AudioMime)
	payload.SeededIntro = strings.TrimSpace(payload.SeededIntro)
	payload.SeededSource = strings.TrimSpace(payload.SeededSource)
	if len(payload.SeededCategories) > 0 {
		categories := make([]string, 0, len(payload.SeededCategories))
		for _, raw := range payload.SeededCategories {
			if trimmed := strings.TrimSpace(raw); trimmed != "" {
				categories = append(categories, trimmed)
			}
		}
		payload.SeededCategories = categories
	}

	if payload.SessionID == "" {
		return payload, http.StatusBadRequest, "missing_session"
	}
	if payload.Text == "" && payload.AudioBase64 == "" {
		return payload, http.StatusBadRequest, "missing_text"
	}
	if payload.Text == "" && payload.AudioBase64 != "" {
		if _, err := base64.StdEncoding.DecodeString(payload.AudioBase64); err != nil {
			return payload, http.StatusBadRequest, "invalid_audio"
		}
		payload.Text = "User sent a voice message."
	}
	return payload, 0, ""
}
