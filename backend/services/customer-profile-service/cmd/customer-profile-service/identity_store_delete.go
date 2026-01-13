package main

import (
	"context"

	cloudfirestore "cloud.google.com/go/firestore"
)

func deleteIdentity(
	ctx context.Context,
	client *cloudfirestore.Client,
	channel string,
	userID string,
) error {
	docID := identityDocID(channel, userID)
	if docID == "" {
		return nil
	}
	_, err := client.Collection(identitiesCollection).Doc(docID).Delete(ctx)
	return err
}
