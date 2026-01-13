package main

import (
	"context"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func writeCustomerEvent(
	ctx context.Context,
	client *cloudfirestore.Client,
	customerID string,
	eventType string,
	channel string,
	userID string,
	metadata map[string]string,
) {
	if customerID == "" || eventType == "" {
		return
	}
	eventID, err := newRandomID(12)
	if err != nil {
		return
	}
	record := customerEvent{
		CustomerID: customerID,
		EventType:  eventType,
		Channel:    normalizeChannel(channel),
		UserID:     userID,
		CreatedAt:  time.Now().UTC(),
		Metadata:   metadata,
	}
	_, _ = client.Collection(customerEventsCollection).Doc(eventID).Set(ctx, record)
}
