package main

import (
	"context"
	"errors"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func completeFuelOrder(
	ctx context.Context,
	client *cloudfirestore.Client,
	cfg *serviceConfig,
	orderID string,
	payload fuelCompleteRequest,
	reqCtx context.Context,
) (*orderRecord, error) {
	record, err := fetchOrder(ctx, client, orderID)
	if err != nil {
		return nil, err
	}
	if record == nil {
		return nil, errOrderNotFound
	}
	if cfg.RequireAuth && !canAccessStore(reqCtx, record.StoreID) {
		return nil, errUnauthorizedStore
	}
	if !isGasStationBusinessType(record.BusinessType) || record.Fuel == nil {
		return nil, errors.New("not_gas_order")
	}
	if record.Status != statusReady && record.Status != statusConfirmed {
		return nil, errInvalidTransition
	}

	finalLiters, finalAmount, err := resolveFuelCompletionTotals(record, payload)
	if err != nil {
		return nil, err
	}
	if record.Fuel.PaymentFlow == fuelPaymentFlowPreauth {
		if cfg.PaymentsServiceURL == "" {
			return nil, errors.New("payments_service_not_configured")
		}
		if err := captureFuelPayment(ctx, cfg.PaymentsServiceURL, orderID, finalAmount); err != nil {
			return nil, err
		}
	}

	err = client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(client.Collection(ordersCollection).Doc(orderID))
		if err != nil {
			if status.Code(err) == codes.NotFound {
				return errOrderNotFound
			}
			return err
		}
		var latest orderRecord
		if err := snap.DataTo(&latest); err != nil {
			return err
		}
		if cfg.RequireAuth && !canAccessStore(reqCtx, latest.StoreID) {
			return errUnauthorizedStore
		}
		if latest.Status != statusReady && latest.Status != statusConfirmed {
			return errInvalidTransition
		}
		if latest.Fuel == nil {
			return errors.New("missing_fuel")
		}
		now := time.Now().UTC()
		latest.Fuel.FinalLiters = finalLiters
		latest.Fuel.FinalAmountCents = finalAmount
		latest.StatusChange = &orderStatusChange{
			PreviousStatus: latest.Status,
			NewStatus:      statusCompleted,
			ChangedAt:      now,
			ChangedBy:      authUID(reqCtx),
			NotifyMode:     notifyModeAuto,
		}
		latest.Status = statusCompleted
		if latest.CompletedAt == nil {
			t := now
			latest.CompletedAt = &t
		}
		latest.SubtotalCents = finalAmount
		latest.TotalCents = finalAmount
		latest.UpdatedAt = now
		return tx.Set(client.Collection(ordersCollection).Doc(orderID), latest)
	})
	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
}
