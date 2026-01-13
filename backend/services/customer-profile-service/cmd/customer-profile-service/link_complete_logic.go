package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func processLinkComplete(
	ctx context.Context,
	fs *cloudfirestore.Client,
	payload linkCompleteRequest,
) (customerRecord, []customerIdentity, error) {
	token, err := validateLinkToken(ctx, fs, payload.Token, payload.Channel)
	if err != nil {
		return customerRecord{}, nil, err
	}
	target, err := resolveActiveCustomer(ctx, fs, token.CustomerID)
	if err != nil {
		return customerRecord{}, nil, err
	}
	target, err = ensureCustomerConsent(ctx, fs, target, payload.Consent)
	if err != nil {
		return customerRecord{}, nil, err
	}
	identity, found, err := fetchIdentity(ctx, fs, payload.Channel, payload.UserID)
	if err != nil {
		return customerRecord{}, nil, err
	}
	if !found {
		return linkNewIdentity(ctx, fs, target, token, payload)
	}
	return linkExistingIdentity(ctx, fs, target, token, payload, identity)
}

func linkNewIdentity(
	ctx context.Context,
	fs *cloudfirestore.Client,
	target customerRecord,
	token linkTokenRecord,
	payload linkCompleteRequest,
) (customerRecord, []customerIdentity, error) {
	now := time.Now().UTC()
	identity := customerIdentity{
		CustomerID:  target.CustomerID,
		Channel:     payload.Channel,
		UserID:      payload.UserID,
		DisplayName: strings.TrimSpace(payload.DisplayName),
		LinkedAt:    now,
		LastSeenAt:  now,
		VerifiedAt:  now,
	}
	if err := upsertIdentity(ctx, fs, identity); err != nil {
		return customerRecord{}, nil, err
	}
	seen := buildSeenContext(payload.Channel, "", "", "")
	_ = touchCustomer(ctx, fs, target, payload.DisplayName, seen)
	_ = markLinkTokenUsed(ctx, fs, token.Token, payload.Channel, payload.UserID)
	writeCustomerEvent(ctx, fs, target.CustomerID, "identity_linked", payload.Channel, payload.UserID, nil)
	identities, _ := listIdentitiesByCustomer(ctx, fs, target.CustomerID)
	return target, identities, nil
}

func linkExistingIdentity(
	ctx context.Context,
	fs *cloudfirestore.Client,
	target customerRecord,
	token linkTokenRecord,
	payload linkCompleteRequest,
	identity customerIdentity,
) (customerRecord, []customerIdentity, error) {
	source, err := resolveActiveCustomer(ctx, fs, identity.CustomerID)
	if err != nil {
		return customerRecord{}, nil, err
	}
	if _, err := ensureCustomerConsent(ctx, fs, source, payload.Consent); err != nil {
		return customerRecord{}, nil, err
	}
	if source.CustomerID != target.CustomerID {
		if err := mergeCustomers(ctx, fs, source.CustomerID, target.CustomerID); err != nil {
			return customerRecord{}, nil, err
		}
	}
	now := time.Now().UTC()
	identity.CustomerID = target.CustomerID
	identity.DisplayName = chooseDisplayName(identity.DisplayName, payload.DisplayName)
	identity.LastSeenAt = now
	identity.VerifiedAt = now
	if err := upsertIdentity(ctx, fs, identity); err != nil {
		return customerRecord{}, nil, err
	}
	seen := buildSeenContext(payload.Channel, "", "", "")
	_ = touchCustomer(ctx, fs, target, payload.DisplayName, seen)
	_ = markLinkTokenUsed(ctx, fs, token.Token, payload.Channel, payload.UserID)
	writeCustomerEvent(ctx, fs, target.CustomerID, "identity_linked", payload.Channel, payload.UserID, nil)
	identities, _ := listIdentitiesByCustomer(ctx, fs, target.CustomerID)
	return target, identities, nil
}
