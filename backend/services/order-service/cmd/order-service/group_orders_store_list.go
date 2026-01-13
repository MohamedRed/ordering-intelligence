package main

import (
	"context"
	"errors"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func listGroupOrders(
	ctx context.Context,
	client *cloudfirestore.Client,
	storeID string,
	statusFilter string,
	limit int,
) ([]groupOrderSession, error) {
	collection := client.Collection(groupOrdersCollection).Where("storeId", "==", storeID)
	if statusFilter != "" {
		collection = collection.Where("status", "==", statusFilter)
	}
	iter := collection.OrderBy("createdAt", cloudfirestore.Desc).Limit(limit).Documents(ctx)
	defer iter.Stop()

	var results []groupOrderSession
	for {
		snap, err := iter.Next()
		if err != nil {
			if errors.Is(err, iterator.Done) {
				break
			}
			return nil, err
		}
		var session groupOrderSession
		if err := snap.DataTo(&session); err != nil {
			return nil, err
		}
		results = append(results, session)
	}
	return results, nil
}
