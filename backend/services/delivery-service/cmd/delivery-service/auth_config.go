package main

import (
	"fmt"
	"strings"
)

func validateDeliveryAuthConfig(cfg *serviceConfig) error {
	if cfg == nil || !cfg.RequireAuth || !isStrictDeliveryEnvironment(cfg.Environment) {
		return nil
	}

	missing := []string{}
	if strings.TrimSpace(cfg.OrdersEventsAudience) == "" {
		missing = append(missing, "ORDERS_EVENTS_OIDC_AUDIENCE")
	}
	if len(cfg.OrdersEventsAllowedEmails) == 0 {
		missing = append(missing, "ORDERS_EVENTS_OIDC_ALLOWED_EMAILS")
	}
	if len(missing) > 0 {
		return fmt.Errorf("delivery-service Pub/Sub push auth config missing required values in staging/production: %s", strings.Join(missing, ", "))
	}
	return nil
}
