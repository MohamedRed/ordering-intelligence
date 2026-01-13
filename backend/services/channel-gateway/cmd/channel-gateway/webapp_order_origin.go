package main

import "strings"

type orderOrigin struct {
	SessionID      string `json:"sessionId,omitempty"`
	AuthProvider   string `json:"authProvider,omitempty"`
	ClientPlatform string `json:"clientPlatform,omitempty"`
	ClientApp      string `json:"clientApp,omitempty"`
	ClientVersion  string `json:"clientVersion,omitempty"`
}

func buildWebAppOrderOrigin(session channelSession, sessionID string) *orderOrigin {
	sessionID = strings.TrimSpace(sessionID)
	provider := strings.TrimSpace(session.AuthProvider)
	if provider == "" {
		provider = strings.TrimSpace(webAppAuthProvider(session.Channel))
	}
	platform := strings.TrimSpace(session.ClientPlatform)
	app := strings.TrimSpace(session.ClientApp)
	version := strings.TrimSpace(session.ClientVersion)

	if platform == "" {
		if strings.EqualFold(strings.TrimSpace(session.Channel), "mobile") {
			platform = "mobile"
		} else {
			platform = "web"
		}
	}
	if app == "" {
		if isMobilePlatform(platform) {
			app = "consumer-mobile"
		} else {
			app = "consumer-web"
		}
	}
	if sessionID == "" && provider == "" && platform == "" && app == "" && version == "" {
		return nil
	}
	return &orderOrigin{
		SessionID:      sessionID,
		AuthProvider:   provider,
		ClientPlatform: platform,
		ClientApp:      app,
		ClientVersion:  version,
	}
}

func isMobilePlatform(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "mobile", "ios", "android":
		return true
	default:
		return false
	}
}
