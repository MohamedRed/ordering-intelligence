package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func identityDocID(channel, userID string) string {
	channel = normalizeChannel(channel)
	userID = strings.TrimSpace(userID)
	if channel == "" || userID == "" {
		return ""
	}
	safeUser := strings.ReplaceAll(userID, "/", "_")
	return strings.Join([]string{channel, safeUser}, ":")
}

func fetchIdentity(ctx context.Context, client *cloudfirestore.Client, channel, userID string) (customerIdentity, bool, error) {
	docID := identityDocID(channel, userID)
	if docID == "" {
		return customerIdentity{}, false, nil
	}
	doc, err := client.Collection(identitiesCollection).Doc(docID).Get(ctx)
	if err != nil || !doc.Exists() {
		return customerIdentity{}, false, nil
	}
	var identity customerIdentity
	if err := doc.DataTo(&identity); err != nil {
		return customerIdentity{}, false, err
	}
	return identity, true, nil
}

func upsertIdentity(ctx context.Context, client *cloudfirestore.Client, identity customerIdentity) error {
	docID := identityDocID(identity.Channel, identity.UserID)
	if docID == "" {
		return nil
	}
	identity.Channel = normalizeChannel(identity.Channel)
	if identity.LinkedAt.IsZero() {
		identity.LinkedAt = time.Now().UTC()
	}
	if identity.LastSeenAt.IsZero() {
		identity.LastSeenAt = time.Now().UTC()
	}
	_, err := client.Collection(identitiesCollection).Doc(docID).Set(ctx, identity, cloudfirestore.MergeAll)
	return err
}

func listIdentitiesByCustomer(ctx context.Context, client *cloudfirestore.Client, customerID string) ([]customerIdentity, error) {
	if customerID == "" {
		return []customerIdentity{}, nil
	}
	iter := client.Collection(identitiesCollection).
		Where("customerId", "==", customerID).
		Documents(ctx)
	identities := []customerIdentity{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return identities, err
		}
		var identity customerIdentity
		if err := doc.DataTo(&identity); err != nil {
			continue
		}
		identities = append(identities, identity)
	}
	return identities, nil
}

func countIdentities(ctx context.Context, client *cloudfirestore.Client, customerID string) (int, error) {
	identities, err := listIdentitiesByCustomer(ctx, client, customerID)
	if err != nil {
		return 0, err
	}
	return len(identities), nil
}
