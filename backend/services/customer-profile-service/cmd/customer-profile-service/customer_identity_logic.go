package main

import (
	"context"
	"log"
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
		log.Printf("fetch identity failed channel=%s user=%s: %v", channel, userID, err)
		found = false
	}
	if !found {
		if fallback, ok, err := findIdentityByFields(ctx, client, channel, userID); err == nil && ok {
			identity = fallback
			found = true
		} else if err != nil {
			log.Printf("fallback identity lookup failed channel=%s user=%s: %v", channel, userID, err)
		}
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
			log.Printf("upsert identity failed customer=%s channel=%s user=%s: %v", customer.CustomerID, channel, userID, err)
		}
		if err := touchCustomer(ctx, client, customer, displayName, seen); err != nil {
			log.Printf("touch customer failed customer=%s: %v", customer.CustomerID, err)
		}
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
		log.Printf("upsert identity failed customer=%s channel=%s user=%s: %v", customer.CustomerID, channel, userID, err)
	}
	writeCustomerEvent(ctx, client, customer.CustomerID, "customer_created", channel, userID, nil)
	return customer, []customerIdentity{identity}, nil
}
