package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func nextOrderDisplayNumber(
	ctx context.Context,
	tx *cloudfirestore.Transaction,
	client *cloudfirestore.Client,
	storeID string,
	createdAt time.Time,
) (string, error) {
	if createdAt.IsZero() {
		createdAt = time.Now().UTC()
	}
	dateKey := createdAt.UTC().Format("20060102")
	docID := orderCounterDocID(storeID, dateKey)
	docRef := client.Collection(orderCountersCollection).Doc(docID)

	snap, err := tx.Get(docRef)
	if err != nil {
		if status.Code(err) != codes.NotFound {
			return "", err
		}
		count := int64(1)
		if err := tx.Create(docRef, map[string]any{
			"storeId":   strings.TrimSpace(storeID),
			"date":      dateKey,
			"count":     count,
			"updatedAt": createdAt.UTC(),
		}); err != nil {
			return "", err
		}
		return formatDisplayNumber(count), nil
	}

	var payload struct {
		Count int64 `firestore:"count"`
	}
	if err := snap.DataTo(&payload); err != nil {
		return "", err
	}
	count := payload.Count + 1
	if err := tx.Set(docRef, map[string]any{
		"storeId":   strings.TrimSpace(storeID),
		"date":      dateKey,
		"count":     count,
		"updatedAt": createdAt.UTC(),
	}, cloudfirestore.MergeAll); err != nil {
		return "", err
	}
	return formatDisplayNumber(count), nil
}

func orderCounterDocID(storeID, dateKey string) string {
	trimmed := strings.TrimSpace(storeID)
	sanitized := strings.NewReplacer("/", "_", " ", "_", ":", "_").Replace(trimmed)
	if sanitized == "" {
		sanitized = "store"
	}
	return fmt.Sprintf("%s_%s", strings.ToLower(sanitized), dateKey)
}

func formatDisplayNumber(count int64) string {
	if count < 1000 {
		return fmt.Sprintf("%03d", count)
	}
	return strconv.FormatInt(count, 10)
}
