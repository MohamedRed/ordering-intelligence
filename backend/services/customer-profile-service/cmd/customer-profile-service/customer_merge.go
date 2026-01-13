package main

import (
	"context"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func mergeCustomers(
	ctx context.Context,
	client *cloudfirestore.Client,
	sourceCustomerID string,
	targetCustomerID string,
) error {
	if sourceCustomerID == "" || targetCustomerID == "" || sourceCustomerID == targetCustomerID {
		return nil
	}
	iter := client.Collection(identitiesCollection).
		Where("customerId", "==", sourceCustomerID).
		Documents(ctx)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		_, _ = doc.Ref.Set(ctx, map[string]any{
			"customerId": targetCustomerID,
			"updatedAt":  time.Now().UTC(),
		}, cloudfirestore.MergeAll)
	}
	return markCustomerMerged(ctx, client, sourceCustomerID, targetCustomerID)
}
