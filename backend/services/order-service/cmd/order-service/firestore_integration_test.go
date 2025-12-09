package main

import (
	"context"
	"os"
	"testing"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func TestCreateAndFetchOrderWithFirestoreEmulator(t *testing.T) {
	if _, ok := os.LookupEnv("FIRESTORE_EMULATOR_HOST"); !ok {
		t.Skip("FIRESTORE_EMULATOR_HOST not set; skipping emulator integration test")
	}

	ctx := context.Background()
	projectID := os.Getenv("FIRESTORE_PROJECT_ID")
	if projectID == "" {
		projectID = "demo-ordering-intelligence"
	}

	client, err := cloudfirestore.NewClient(ctx, projectID)
	if err != nil {
		t.Fatalf("failed to create firestore client: %v", err)
	}
	defer client.Close()

	callSid := "CA-test-firestore"
	order := orderRecord{
		ID:           "order-emulator-test",
		StoreID:      "store-123",
		CallSid:      callSid,
		Channel:      "voice",
		CustomerName: "Test Customer",
		Notes:        "extra spicy",
		Items: []orderItem{
			{
				ItemID:    "item-1",
				Name:      "Taco",
				Quantity:  2,
				Modifiers: []modifierSelection{
					{Name: "jalapeno", Price: 0},
				},
				PriceCents: 900,
				Category:   "food",
			},
		},
		Status:    "pending",
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}

	t.Cleanup(func() {
		_, _ = client.Collection(ordersCollection).Doc(order.ID).Delete(ctx)
	})

	if err := createOrder(ctx, client, order, ""); err != nil {
		t.Fatalf("failed to create order: %v", err)
	}

	record, err := fetchOrderByCallSid(ctx, client, callSid)
	if err != nil {
		t.Fatalf("failed to fetch order: %v", err)
	}
	if record == nil {
		t.Fatalf("expected order record, got nil")
	}
	if record.ID != order.ID {
		t.Fatalf("expected order ID %s, got %s", order.ID, record.ID)
	}
	if record.StoreID != order.StoreID {
		t.Fatalf("expected store %s, got %s", order.StoreID, record.StoreID)
	}
}
