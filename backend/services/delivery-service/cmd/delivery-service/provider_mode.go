package main

import (
	"fmt"
	"strings"
)

const (
	deliveryProviderModeMock = "mock"
	deliveryProviderModeLive = "live"

	deliveryProviderMock = "mock"
)

func resolveDeliveryProviderMode(raw string, environment string) (string, error) {
	mode := strings.ToLower(strings.TrimSpace(raw))
	if mode == "" {
		mode = deliveryProviderModeMock
	}

	switch mode {
	case deliveryProviderModeMock, deliveryProviderModeLive:
	default:
		return "", fmt.Errorf("PROVIDER_MODE must be one of %q or %q", deliveryProviderModeMock, deliveryProviderModeLive)
	}

	if mode == deliveryProviderModeMock && isStrictDeliveryEnvironment(environment) {
		return "", fmt.Errorf("PROVIDER_MODE=%q is not allowed in %s", deliveryProviderModeMock, environment)
	}

	return mode, nil
}

func isStrictDeliveryEnvironment(environment string) bool {
	switch strings.ToLower(strings.TrimSpace(environment)) {
	case "prod", "production", "staging":
		return true
	default:
		return false
	}
}

func validateDeliveryProviderConfig(cfg *serviceConfig) error {
	if cfg.ProviderMode != deliveryProviderModeLive {
		return nil
	}
	if hasUberDirectCredentials(cfg) || hasStuartCredentials(cfg) {
		return nil
	}
	return fmt.Errorf("PROVIDER_MODE=%q requires configured Uber Direct or Stuart credentials", deliveryProviderModeLive)
}

func hasUberDirectCredentials(cfg *serviceConfig) bool {
	if strings.TrimSpace(cfg.UberDirectCustomerID) == "" {
		return false
	}
	return strings.TrimSpace(cfg.UberDirectAccessToken) != "" ||
		strings.TrimSpace(cfg.UberDirectAPIKey) != "" ||
		(strings.TrimSpace(cfg.UberDirectClientID) != "" && strings.TrimSpace(cfg.UberDirectClientSecret) != "")
}

func hasStuartCredentials(cfg *serviceConfig) bool {
	return strings.TrimSpace(cfg.StuartAccessToken) != "" ||
		strings.TrimSpace(cfg.StuartAPIKey) != "" ||
		(strings.TrimSpace(cfg.StuartClientID) != "" && strings.TrimSpace(cfg.StuartClientSecret) != "")
}

func defaultQuoteCandidates(providerMode string) []string {
	if providerMode == deliveryProviderModeMock {
		return []string{deliveryProviderMock}
	}
	return nil
}

func containsProviderCandidate(candidates []string, provider string) bool {
	normalized := normalizeProvider(provider)
	for _, candidate := range candidates {
		if normalizeProvider(candidate) == normalized {
			return true
		}
	}
	return false
}
