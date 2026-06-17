package main

import (
	"context"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

var createGroupOrderFn = createGroupOrder
var fetchGroupOrderFn = fetchGroupOrder
var updateGroupOrderFn = updateGroupOrder

func createGroupOrder(ctx context.Context, client *cloudfirestore.Client, session groupOrderSession) error {
	session.CreatedAt = time.Now().UTC()
	session.UpdatedAt = session.CreatedAt
	_, err := client.Collection(groupOrdersCollection).Doc(session.ID).Create(ctx, session)
	return err
}

func fetchGroupOrder(ctx context.Context, client *cloudfirestore.Client, id string) (groupOrderSession, error) {
	snap, err := client.Collection(groupOrdersCollection).Doc(id).Get(ctx)
	if err != nil {
		return groupOrderSession{}, err
	}
	var session groupOrderSession
	if err := snap.DataTo(&session); err != nil {
		return groupOrderSession{}, err
	}
	return session, nil
}

func updateGroupOrder(ctx context.Context, client *cloudfirestore.Client, id string, mutate func(groupOrderSession) (groupOrderSession, error)) (groupOrderSession, error) {
	var updated groupOrderSession
	err := client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		docRef := client.Collection(groupOrdersCollection).Doc(id)
		snap, err := tx.Get(docRef)
		if err != nil {
			return err
		}
		var current groupOrderSession
		if err := snap.DataTo(&current); err != nil {
			return err
		}
		next, err := mutate(current)
		if err != nil {
			return err
		}
		if next.CreatedAt.IsZero() {
			next.CreatedAt = current.CreatedAt
		}
		next.UpdatedAt = time.Now().UTC()
		updated = next
		return tx.Set(docRef, next)
	})
	return updated, err
}
