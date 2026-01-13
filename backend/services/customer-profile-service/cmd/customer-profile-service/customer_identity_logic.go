package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func resolveCustomerForIdentity(
	ctx context.Context,
	client *cloudfirestore.Client,
	channel string,
	userID string,
	displayName string,
	allowCreate bool,
	seen customerSeenContext,
) (customerRecord, []customerIdentity, error) {
	channel = normalizeChannel(channel)
	userID = strings.TrimSpace(userID)
	if channel == "" || userID == "" {
		return customerRecord{}, nil, errCustomerNotFound
	}
	seen = buildSeenContext(channel, seen.StoreID, seen.Platform, seen.Provider)

	identity, found, err := fetchIdentity(ctx, client, channel, userID)
	if err != nil {
		return customerRecord{}, nil, err
	}
	if found {
		customer, err := resolveActiveCustomer(ctx, client, identity.CustomerID)
		if err != nil {
			return customerRecord{}, nil, err
		}
		identity.CustomerID = customer.CustomerID
		identity.DisplayName = chooseDisplayName(identity.DisplayName, displayName)
		identity.LastSeenAt = time.Now().UTC()
		if err := upsertIdentity(ctx, client, identity); err != nil {
			return customerRecord{}, nil, err
		}
		_ = touchCustomer(ctx, client, customer, displayName, seen)
		linked, _ := listIdentitiesByCustomer(ctx, client, customer.CustomerID)
		return customer, linked, nil
	}
	if !allowCreate {
		return customerRecord{}, nil, errCustomerNotFound
	}
	customer, err := createCustomer(ctx, client, displayName, seen)
	if err != nil {
		return customerRecord{}, nil, err
	}
	identity = customerIdentity{
		CustomerID:  customer.CustomerID,
		Channel:     channel,
		UserID:      userID,
		DisplayName: strings.TrimSpace(displayName),
		LinkedAt:    time.Now().UTC(),
		LastSeenAt:  time.Now().UTC(),
		VerifiedAt:  time.Now().UTC(),
	}
	if err := upsertIdentity(ctx, client, identity); err != nil {
		return customerRecord{}, nil, err
	}
	writeCustomerEvent(ctx, client, customer.CustomerID, "customer_created", channel, userID, nil)
	return customer, []customerIdentity{identity}, nil
}
