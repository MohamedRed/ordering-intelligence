package main

import (
	"context"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func createLinkToken(
	ctx context.Context,
	client *cloudfirestore.Client,
	customerID string,
	targetChannel string,
	ttl time.Duration,
) (linkTokenRecord, error) {
	token, err := newLinkToken()
	if err != nil {
		return linkTokenRecord{}, err
	}
	now := time.Now().UTC()
	record := linkTokenRecord{
		Token:         token,
		CustomerID:    customerID,
		TargetChannel: normalizeChannel(targetChannel),
		CreatedAt:     now,
		ExpiresAt:     now.Add(ttl),
	}
	if _, err := client.Collection(linkTokensCollection).Doc(token).Set(ctx, record); err != nil {
		return linkTokenRecord{}, err
	}
	return record, nil
}

func fetchLinkToken(ctx context.Context, client *cloudfirestore.Client, token string) (linkTokenRecord, bool, error) {
	doc, err := client.Collection(linkTokensCollection).Doc(token).Get(ctx)
	if err != nil || !doc.Exists() {
		return linkTokenRecord{}, false, nil
	}
	var record linkTokenRecord
	if err := doc.DataTo(&record); err != nil {
		return linkTokenRecord{}, false, err
	}
	return record, true, nil
}

func markLinkTokenUsed(
	ctx context.Context,
	client *cloudfirestore.Client,
	token string,
	channel string,
	userID string,
) error {
	updates := map[string]any{
		"usedAt":        time.Now().UTC(),
		"usedByChannel": normalizeChannel(channel),
		"usedByUserId":  userID,
	}
	_, err := client.Collection(linkTokensCollection).Doc(token).Set(ctx, updates, cloudfirestore.MergeAll)
	return err
}
