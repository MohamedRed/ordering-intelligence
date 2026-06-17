package main

import (
	"errors"
	"net/http"
	"strings"
)

var errWebAppSessionMissingStore = errors.New("session_store_missing")
var errWebAppSessionStoreForbidden = errors.New("session_store_forbidden")

func resolveWebAppSessionStore(session channelSession, requestedStoreID string) (string, error) {
	sessionStoreID := strings.TrimSpace(session.StoreID)
	if sessionStoreID == "" {
		return "", errWebAppSessionMissingStore
	}
	requestedStoreID = strings.TrimSpace(requestedStoreID)
	if requestedStoreID != "" && requestedStoreID != sessionStoreID {
		return "", errWebAppSessionStoreForbidden
	}
	return sessionStoreID, nil
}

func writeWebAppSessionStoreAccessError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errWebAppSessionMissingStore):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "session_store_missing"})
	case errors.Is(err, errWebAppSessionStoreForbidden):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "store_access_failed"})
	}
}
