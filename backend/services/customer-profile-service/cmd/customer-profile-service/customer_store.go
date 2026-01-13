package main

import (
	"context"
	"errors"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

var errCustomerNotFound = errors.New("customer_not_found")

func fetchCustomer(ctx context.Context, client *cloudfirestore.Client, customerID string) (customerRecord, error) {
	if customerID == "" {
		return customerRecord{}, errCustomerNotFound
	}
	doc, err := client.Collection(customersCollection).Doc(customerID).Get(ctx)
	if err != nil || !doc.Exists() {
		return customerRecord{}, errCustomerNotFound
	}
	var record customerRecord
	if err := doc.DataTo(&record); err != nil {
		return customerRecord{}, err
	}
	return record, nil
}

func createCustomer(
	ctx context.Context,
	client *cloudfirestore.Client,
	displayName string,
	seen customerSeenContext,
) (customerRecord, error) {
	id, err := newCustomerID()
	if err != nil {
		return customerRecord{}, err
	}
	now := time.Now().UTC()
	record := customerRecord{
		CustomerID:  id,
		DisplayName: strings.TrimSpace(displayName),
		Status:      "active",
		CreatedAt:   now,
		UpdatedAt:   now,
		FirstSeenAt: now,
		LastSeenAt:  now,
	}
	if seen.Channel != "" {
		record.FirstSeenChannel = seen.Channel
		record.LastSeenChannel = seen.Channel
	}
	if seen.StoreID != "" {
		record.FirstSeenStoreID = seen.StoreID
		record.LastSeenStoreID = seen.StoreID
	}
	if seen.Platform != "" {
		record.FirstSeenPlatform = seen.Platform
		record.LastSeenPlatform = seen.Platform
	}
	if seen.Provider != "" {
		record.FirstSeenProvider = seen.Provider
		record.LastSeenProvider = seen.Provider
	}
	if _, err := client.Collection(customersCollection).Doc(id).Set(ctx, record); err != nil {
		return customerRecord{}, err
	}
	return record, nil
}

func touchCustomer(
	ctx context.Context,
	client *cloudfirestore.Client,
	record customerRecord,
	displayName string,
	seen customerSeenContext,
) error {
	now := time.Now().UTC()
	updates := map[string]any{
		"lastSeenAt": now,
		"updatedAt":  now,
	}
	if record.FirstSeenAt.IsZero() {
		updates["firstSeenAt"] = now
	}
	if strings.TrimSpace(displayName) != "" && strings.TrimSpace(record.DisplayName) == "" {
		updates["displayName"] = strings.TrimSpace(displayName)
	}
	if record.FirstSeenChannel == "" && seen.Channel != "" {
		updates["firstSeenChannel"] = seen.Channel
	}
	if record.FirstSeenStoreID == "" && seen.StoreID != "" {
		updates["firstSeenStoreId"] = seen.StoreID
	}
	if record.FirstSeenPlatform == "" && seen.Platform != "" {
		updates["firstSeenPlatform"] = seen.Platform
	}
	if record.FirstSeenProvider == "" && seen.Provider != "" {
		updates["firstSeenProvider"] = seen.Provider
	}
	if seen.Channel != "" {
		updates["lastSeenChannel"] = seen.Channel
	}
	if seen.StoreID != "" {
		updates["lastSeenStoreId"] = seen.StoreID
	}
	if seen.Platform != "" {
		updates["lastSeenPlatform"] = seen.Platform
	}
	if seen.Provider != "" {
		updates["lastSeenProvider"] = seen.Provider
	}
	_, err := client.Collection(customersCollection).Doc(record.CustomerID).Set(ctx, updates, cloudfirestore.MergeAll)
	return err
}

func markCustomerMerged(ctx context.Context, client *cloudfirestore.Client, sourceID, targetID string) error {
	now := time.Now().UTC()
	updates := map[string]any{
		"status":     "merged",
		"mergedInto": targetID,
		"updatedAt":  now,
	}
	_, err := client.Collection(customersCollection).Doc(sourceID).Set(ctx, updates, cloudfirestore.MergeAll)
	return err
}
