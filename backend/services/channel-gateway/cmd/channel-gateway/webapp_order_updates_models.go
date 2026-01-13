package main

import "strings"

type webAppOrderUpdatesLinkRequest struct {
	SessionID string `json:"sessionId"`
}

type webAppOrderUpdatesLinkResponse struct {
	Linked         bool `json:"linked"`
	MessageSent    bool `json:"messageSent"`
	NeedsUserStart bool `json:"needsUserStart"`
}

func requiresTelegramStart(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "status=403") || strings.Contains(msg, "forbidden")
}
