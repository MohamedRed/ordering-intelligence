package main

import (
	"context"
	"errors"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func updateFuelPumpNumber(
	ctx context.Context,
	client *cloudfirestore.Client,
	orderID string,
	pumpNumber string,
	reqCtx context.Context,
	requireAuth bool,
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
		if !isGasStationBusinessType(record.BusinessType) || record.Fuel == nil {
			return errors.New("not_gas_order")
		}
		if record.Status == statusCompleted || record.Status == statusCancelled {
			return errInvalidTransition
		}
		record.Fuel.PumpNumber = strings.TrimSpace(pumpNumber)
		record.UpdatedAt = time.Now().UTC()
		return tx.Set(docRef, record)
	})
	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
}
