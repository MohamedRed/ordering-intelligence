package main

import (
	"strings"
	"time"
)

func resolveQuoteCandidates(providerOverride string, settings *storeDeliverySettings, providerMode string) ([]string, string) {
	if providerOverride != "" {
		return []string{normalizeProvider(providerOverride)}, "single"
	}
	if settings != nil {
		mode := strings.ToLower(strings.TrimSpace(settings.ProviderSelectionMode))
		switch mode {
		case "auto":
			candidates := normalizeProviders(settings.EnabledProviders)
			if len(candidates) > 0 {
				return candidates, "auto"
			}
		case "single":
			// Fall through to primary provider.
		}
		if settings.PrimaryProvider != "" {
			return []string{normalizeProvider(settings.PrimaryProvider)}, "single"
		}
	}
	return defaultQuoteCandidates(providerMode), "single"
}

func selectQuote(quotes []deliveryQuote, mode string, settings *storeDeliverySettings) deliveryQuote {
	if len(quotes) == 0 {
		return deliveryQuote{}
	}
	if mode != "auto" || len(quotes) == 1 {
		return quotes[0]
	}

	policy := deliveryRoutingPolicy{OptimizeFor: "eta"}
	primary := ""
	if settings != nil {
		if settings.RoutingPolicy.OptimizeFor != "" {
			policy.OptimizeFor = settings.RoutingPolicy.OptimizeFor
		}
		if settings.RoutingPolicy.MaxEtaMinutes > 0 {
			policy.MaxEtaMinutes = settings.RoutingPolicy.MaxEtaMinutes
		}
		if settings.RoutingPolicy.MaxProviderFeeCents > 0 {
			policy.MaxProviderFeeCents = settings.RoutingPolicy.MaxProviderFeeCents
		}
		primary = settings.PrimaryProvider
	}

	filtered := make([]deliveryQuote, 0, len(quotes))
	for _, q := range quotes {
		if policy.MaxEtaMinutes > 0 && q.DropoffEtaMinutes > policy.MaxEtaMinutes {
			continue
		}
		if policy.MaxProviderFeeCents > 0 && q.ProviderFeeCents > policy.MaxProviderFeeCents {
			continue
		}
		filtered = append(filtered, q)
	}
	if len(filtered) == 0 {
		filtered = quotes
	}

	best := filtered[0]
	bestScore := scoreQuote(best, policy)
	for _, q := range filtered[1:] {
		score := scoreQuote(q, policy)
		if score < bestScore {
			best = q
			bestScore = score
			continue
		}
		if score == bestScore && primary != "" && q.Provider == primary {
			best = q
			bestScore = score
		}
	}
	return best
}

func scoreQuote(q deliveryQuote, policy deliveryRoutingPolicy) float64 {
	switch strings.ToLower(strings.TrimSpace(policy.OptimizeFor)) {
	case "cost":
		return float64(q.ProviderFeeCents)
	case "balanced":
		return float64(q.DropoffEtaMinutes) + (float64(q.ProviderFeeCents) / 100.0)
	default:
		return float64(q.DropoffEtaMinutes)
	}
}

func mockProviderQuote(provider string) deliveryQuote {
	provider = normalizeProvider(provider)
	fee := int64(699)
	eta := int64(25)
	display := ""
	switch provider {
	case "uber_direct":
		fee = 799
		eta = 22
		display = "Uber Direct"
	case "stuart":
		fee = 699
		eta = 27
		display = "Stuart"
	case deliveryProviderMock:
		display = "Mock Courier"
	default:
		display = strings.ReplaceAll(provider, "_", " ")
	}
	return deliveryQuote{
		Provider:            provider,
		ProviderFeeCents:    fee,
		DropoffEtaMinutes:   eta,
		QuoteExpiresAt:      time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
		Currency:            "USD",
		ProviderDisplayName: display,
	}
}
