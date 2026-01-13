package main

import "strings"

type orderOrigin struct {
	SessionID      string `json:"sessionId,omitempty" firestore:"sessionId,omitempty"`
	AuthProvider   string `json:"authProvider,omitempty" firestore:"authProvider,omitempty"`
	ClientPlatform string `json:"clientPlatform,omitempty" firestore:"clientPlatform,omitempty"`
	ClientApp      string `json:"clientApp,omitempty" firestore:"clientApp,omitempty"`
	ClientVersion  string `json:"clientVersion,omitempty" firestore:"clientVersion,omitempty"`
}

func normalizeOrderOrigin(origin *orderOrigin) *orderOrigin {
	if origin == nil {
		return nil
	}
	out := &orderOrigin{
		SessionID:      strings.TrimSpace(origin.SessionID),
		AuthProvider:   strings.ToLower(strings.TrimSpace(origin.AuthProvider)),
		ClientPlatform: strings.ToLower(strings.TrimSpace(origin.ClientPlatform)),
		ClientApp:      strings.TrimSpace(origin.ClientApp),
		ClientVersion:  strings.TrimSpace(origin.ClientVersion),
	}
	if out.SessionID == "" && out.AuthProvider == "" && out.ClientPlatform == "" && out.ClientApp == "" && out.ClientVersion == "" {
		return nil
	}
	return out
}
