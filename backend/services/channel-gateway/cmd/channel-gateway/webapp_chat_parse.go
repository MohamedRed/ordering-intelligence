package main

import (
	"encoding/json"
	"strings"
)

func parseWebAppChatResponse(text string) webappChatTurnResponse {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return webappChatTurnResponse{
			Messages: []webappChatMessage{{Role: "assistant", Text: ""}},
		}
	}

	var parsed webappChatTurnResponse
	if json.Unmarshal([]byte(trimmed), &parsed) == nil {
		normalized := normalizeWebAppChatResponse(parsed)
		if len(normalized.Messages) > 0 || len(normalized.ToolCalls) > 0 {
			return normalized
		}
	}

	var raw map[string]any
	if json.Unmarshal([]byte(trimmed), &raw) == nil {
		if textValue, ok := raw["text"].(string); ok && strings.TrimSpace(textValue) != "" {
			return webappChatTurnResponse{
				Messages: []webappChatMessage{{Role: "assistant", Text: textValue}},
			}
		}
	}

	return webappChatTurnResponse{
		Messages: []webappChatMessage{{Role: "assistant", Text: text}},
	}
}

func normalizeWebAppChatResponse(resp webappChatTurnResponse) webappChatTurnResponse {
	messages := make([]webappChatMessage, 0, len(resp.Messages))
	for _, msg := range resp.Messages {
		role := strings.TrimSpace(msg.Role)
		if role == "" {
			role = "assistant"
		}
		msg.Role = role
		if strings.TrimSpace(msg.Text) == "" && len(msg.Options) == 0 && len(msg.Products) == 0 {
			continue
		}
		messages = append(messages, msg)
	}
	resp.Messages = messages
	return resp
}
