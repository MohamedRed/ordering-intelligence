package main

import (
	"context"
	"net/http"
	"strings"

	"google.golang.org/api/idtoken"
)

type internalAuthContext struct {
	Email string
}

func requireInternalAuth(cfg *serviceConfig, w http.ResponseWriter, r *http.Request) (internalAuthContext, bool) {
	audience := strings.TrimSpace(cfg.InternalAuthAudience)
	if audience == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "internal_auth_not_configured"})
		return internalAuthContext{}, false
	}
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
		return internalAuthContext{}, false
	}
	token := strings.TrimSpace(authHeader[len("Bearer "):])
	if token == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
		return internalAuthContext{}, false
	}

	payload, err := idtoken.Validate(context.Background(), token, audience)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return internalAuthContext{}, false
	}
	email := ""
	if v, ok := payload.Claims["email"]; ok {
		if s, ok := v.(string); ok {
			email = strings.TrimSpace(s)
		}
	}
	if email == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return internalAuthContext{}, false
	}
	if len(cfg.InternalAllowedEmails) > 0 {
		allowed := false
		for _, entry := range cfg.InternalAllowedEmails {
			if strings.EqualFold(strings.TrimSpace(entry), email) {
				allowed = true
				break
			}
		}
		if !allowed {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return internalAuthContext{}, false
		}
	}
	return internalAuthContext{Email: email}, true
}
