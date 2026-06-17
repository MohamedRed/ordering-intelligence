package main

import (
	"net/http"
	"strings"
)

func verifyMobileSessionRequestAuth(
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
	sessionID string,
	signature string,
	timestamp string,
) bool {
	signature = firstNonEmpty(
		strings.TrimSpace(signature),
		strings.TrimSpace(r.Header.Get("X-Mobile-Auth-Signature")),
		strings.TrimSpace(r.URL.Query().Get("signature")),
	)
	timestamp = firstNonEmpty(
		strings.TrimSpace(timestamp),
		strings.TrimSpace(r.Header.Get("X-Mobile-Auth-Timestamp")),
		strings.TrimSpace(r.URL.Query().Get("timestamp")),
	)
	auth, err := extractMobileAuthParts(signature, timestamp)
	if err == nil {
		if err := verifyMobileSessionIDAuth(cfg, sessionID, auth); err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_invalid"})
			return false
		}
		return true
	}
	if err == errMobileAuthMissing {
		if strings.TrimSpace(cfg.MobileSessionSecret) != "" {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_missing"})
			return false
		}
		if isStrictEnvironment(cfg.Environment) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_not_configured"})
			return false
		}
		return true
	}
	writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "auth_invalid"})
	return false
}
