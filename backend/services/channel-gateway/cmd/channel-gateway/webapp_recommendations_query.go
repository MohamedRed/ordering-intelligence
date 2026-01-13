package main

import (
	"context"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func fetchReorderDocsByCustomerID(
	ctx context.Context,
	client *cloudfirestore.Client,
	customerID string,
) ([]reorderDoc, error) {
	if customerID == "" {
		return []reorderDoc{}, nil
	}
	results := []reorderDoc{}
	query := client.Collection(reordersCollection).
		Where("customerId", "==", customerID)
	iter := query.Documents(ctx)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return results, err
		}
		var rd reorderDoc
		if err := doc.DataTo(&rd); err != nil {
			continue
		}
		results = append(results, rd)
	}
	return results, nil
}
