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

var (
	errOrderContactConflict  = errors.New("channel_contact_conflict")
	errInvalidChannelContact = errors.New("invalid_channel_contact")
)

func updateOrderChannelContact(
	ctx context.Context,
	client *cloudfirestore.Client,
	orderID string,
	contact channelContact,
	reqCtx context.Context,
	requireAuth bool,
) (*orderRecord, error) {
	if strings.TrimSpace(contact.Channel) == "" || strings.TrimSpace(contact.UserID) == "" {
		return nil, errInvalidChannelContact
	}
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

		if record.ChannelContact != nil && !sameChannelContact(record.ChannelContact, &contact) {
			if !canReplaceChannelContact(record.ChannelContact, &contact) {
				return errOrderContactConflict
			}
		}

		record.ChannelContact = &contact
		record.UpdatedAt = time.Now().UTC()
		return tx.Set(docRef, record)
	})
	if err != nil {
		return nil, err
	}
	return fetchOrder(ctx, client, orderID)
}

func sameChannelContact(a, b *channelContact) bool {
	if a == nil || b == nil {
		return false
	}
	if strings.TrimSpace(strings.ToLower(a.Channel)) != strings.TrimSpace(strings.ToLower(b.Channel)) {
		return false
	}
	if strings.TrimSpace(a.UserID) != strings.TrimSpace(b.UserID) {
		return false
	}
	return true
}
