package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func markOrderRefunded(
	ctx context.Context,
	client *cloudfirestore.Client,
	orderID string,
	reqCtx context.Context,
	requireAuth bool,
	note string,
) (*orderRecord, error) {
	docRef := client.Collection(ordersCollection).Doc(orderID)
	err := client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(docRef)
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return errOrderNotFound
			}
			return err
		}
		var record orderRecord
		if err := snap.DataTo(&record); err != nil {
			return err
		}
		if requireAuth && !canAccessStore(reqCtx, record.StoreID) {
			return errUnauthorizedStore
		}
		if record.Status == statusCancelled {
			return nil
		}
		now := time.Now().UTC()
		record.StatusChange = &orderStatusChange{
			PreviousStatus: record.Status,
			NewStatus:      statusCancelled,
			ChangedAt:      now,
			ChangedBy:      authUID(reqCtx),
			NotifyMode:     notifyModeNone,
			Note:           strings.TrimSpace(note),
		}
		if record.CancelledAt == nil {
			t := now
			record.CancelledAt = &t
		}
		record.Status = statusCancelled
		record.UpdatedAt = now
		return tx.Set(docRef, record)
	})
	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
}
