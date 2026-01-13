package main

import (
	"context"
	"errors"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

var (
	errLinkTokenNotFound   = errors.New("link_token_not_found")
	errLinkTokenExpired    = errors.New("link_token_expired")
	errLinkTokenUsed       = errors.New("link_token_used")
	errLinkChannelMismatch = errors.New("link_channel_mismatch")
)

func validateLinkToken(
	ctx context.Context,
	client *cloudfirestore.Client,
	token string,
	channel string,
) (linkTokenRecord, error) {
	record, found, err := fetchLinkToken(ctx, client, token)
	if err != nil {
		return linkTokenRecord{}, err
	}
	if !found {
		return linkTokenRecord{}, errLinkTokenNotFound
	}
	if !record.UsedAt.IsZero() {
		return linkTokenRecord{}, errLinkTokenUsed
	}
	if time.Now().UTC().After(record.ExpiresAt) {
		return linkTokenRecord{}, errLinkTokenExpired
	}
	target := normalizeChannel(record.TargetChannel)
	got := normalizeChannel(channel)
	if target != "" && got != "" && target != got {
		return linkTokenRecord{}, errLinkChannelMismatch
	}
	return record, nil
}
