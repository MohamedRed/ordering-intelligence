package main

import (
	"context"
	"errors"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

var errConsentRequired = errors.New("consent_required")

func resolveActiveCustomer(ctx context.Context, client *cloudfirestore.Client, customerID string) (customerRecord, error) {
	record, err := fetchCustomer(ctx, client, customerID)
	if err != nil {
		return customerRecord{}, err
	}
	if strings.TrimSpace(record.Status) == "merged" && strings.TrimSpace(record.MergedInto) != "" {
		return fetchCustomer(ctx, client, record.MergedInto)
	}
	return record, nil
}

func ensureCustomerConsent(
	ctx context.Context,
	client *cloudfirestore.Client,
	record customerRecord,
	consent bool,
) (customerRecord, error) {
	if !record.LinkedConsentAt.IsZero() {
		return record, nil
	}
	if !consent {
		return record, errConsentRequired
	}
	now := time.Now().UTC()
	updates := map[string]any{
		"linkedConsentAt": now,
		"updatedAt":       now,
	}
	if _, err := client.Collection(customersCollection).Doc(record.CustomerID).Set(ctx, updates, cloudfirestore.MergeAll); err != nil {
		return record, err
	}
	record.LinkedConsentAt = now
	return record, nil
}

func chooseDisplayName(existing, fallback string) string {
	existing = strings.TrimSpace(existing)
	if existing != "" {
		return existing
	}
	return strings.TrimSpace(fallback)
}
