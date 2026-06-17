package main

import (
	"fmt"
	"net/http"
	"strings"
)

func validateDispatchAuthConfig(cfg *serviceConfig) error {
	if cfg == nil {
		return nil
	}
	if isStrictEnvironment(cfg.Environment) && !cfg.RequireAuth {
		return fmt.Errorf("dispatch-service auth cannot be disabled in staging/production")
	}
	if !cfg.RequireAuth {
		return nil
	}

	missing := []string{}
	if isStrictEnvironment(cfg.Environment) {
		if strings.TrimSpace(cfg.InternalAuthAudience) == "" {
			missing = append(missing, "INTERNAL_AUTH_AUDIENCE")
		}
		if len(cfg.InternalAllowedEmails) == 0 {
			missing = append(missing, "INTERNAL_ALLOWED_EMAILS")
		}
	}
	if strings.TrimSpace(cfg.OrdersEventsOIDCAudience) == "" {
		missing = append(missing, "ORDERS_EVENTS_OIDC_AUDIENCE")
	}
	if len(cfg.OrdersEventsOIDCAllowedEmails) == 0 {
		missing = append(missing, "ORDERS_EVENTS_OIDC_ALLOWED_EMAILS")
	}
	if strings.TrimSpace(cfg.CloudTasksOIDCAudience) == "" {
		missing = append(missing, "CLOUD_TASKS_OIDC_AUDIENCE")
	}
	if len(cfg.CloudTasksOIDCAllowedEmails) == 0 {
		missing = append(missing, "CLOUD_TASKS_OIDC_ALLOWED_EMAILS")
	}
	if len(missing) > 0 {
		return fmt.Errorf("dispatch-service auth config missing required values when REQUIRE_AUTH=true: %s", strings.Join(missing, ", "))
	}
	return nil
}

func isStrictEnvironment(environment string) bool {
	switch strings.ToLower(strings.TrimSpace(environment)) {
	case "prod", "production", "staging":
		return true
	default:
		return false
	}
}

func requireDispatchTaskAuth(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	audience string,
	allowedEmails []string,
) bool {
	if cfg != nil && !cfg.RequireAuth {
		return true
	}

	if strings.TrimSpace(audience) == "" || len(allowedEmails) == 0 {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "task_auth_misconfigured"})
		return false
	}

	authHeader := r.Header.Get("Authorization")
	if strings.TrimSpace(authHeader) == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_auth"})
		return false
	}

	tokenString := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
	if tokenString == authHeader || tokenString == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_auth_header"})
		return false
	}

	if ok, _ := tryGoogleIDTokenAuth(r.Context(), tokenString, audience, allowedEmails); !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return false
	}
	return true
}
