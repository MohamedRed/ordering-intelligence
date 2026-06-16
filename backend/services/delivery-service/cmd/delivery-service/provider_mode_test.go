package main

import "testing"

func TestResolveDeliveryProviderModeDefaultsToMockOutsideStrictEnvironments(t *testing.T) {
	mode, err := resolveDeliveryProviderMode("", "development")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if mode != deliveryProviderModeMock {
		t.Fatalf("expected mock mode, got %q", mode)
	}
}

func TestResolveDeliveryProviderModeRejectsMockInStrictEnvironments(t *testing.T) {
	for _, environment := range []string{"staging", "prod", "production"} {
		t.Run(environment, func(t *testing.T) {
			if _, err := resolveDeliveryProviderMode("mock", environment); err == nil {
				t.Fatal("expected strict environment to reject mock provider mode")
			}
		})
	}
}

func TestResolveDeliveryProviderModeRejectsUnknownMode(t *testing.T) {
	if _, err := resolveDeliveryProviderMode("sandbox", "development"); err == nil {
		t.Fatal("expected unknown provider mode to be rejected")
	}
}

func TestValidateDeliveryProviderConfigRequiresLiveCredentials(t *testing.T) {
	cfg := &serviceConfig{ProviderMode: deliveryProviderModeLive}
	if err := validateDeliveryProviderConfig(cfg); err == nil {
		t.Fatal("expected live provider mode to require configured credentials")
	}
}

func TestValidateDeliveryProviderConfigAcceptsUberDirectCredentials(t *testing.T) {
	cfg := &serviceConfig{
		ProviderMode:           deliveryProviderModeLive,
		UberDirectCustomerID:   "customer-123",
		UberDirectClientID:     "client-123",
		UberDirectClientSecret: "secret-123",
	}
	if err := validateDeliveryProviderConfig(cfg); err != nil {
		t.Fatalf("unexpected validation error: %v", err)
	}
}

func TestResolveQuoteCandidatesDoesNotReturnMockFallbackInLiveMode(t *testing.T) {
	candidates, mode := resolveQuoteCandidates("", nil, deliveryProviderModeLive)
	if len(candidates) != 0 {
		t.Fatalf("expected no fallback candidates in live mode, got %#v", candidates)
	}
	if mode != "single" {
		t.Fatalf("unexpected mode: %q", mode)
	}
}

func TestResolveQuoteCandidatesKeepsMockFallbackInMockMode(t *testing.T) {
	candidates, mode := resolveQuoteCandidates("", nil, deliveryProviderModeMock)
	if len(candidates) != 1 || candidates[0] != deliveryProviderMock {
		t.Fatalf("expected mock fallback candidate, got %#v", candidates)
	}
	if mode != "single" {
		t.Fatalf("unexpected mode: %q", mode)
	}
}
