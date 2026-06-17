package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
)

var createOrderFn = createOrder

func handleOrderCreate(
	ctx context.Context,
	firestoreClient *cloudfirestore.Client,
	pubsubClient *cloudpubsub.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
) {
	var payload orderRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if payload.IdempotencyKey == "" {
		payload.IdempotencyKey = r.Header.Get("Idempotency-Key")
	}
	if payload.StoreID == "" || len(payload.Items) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_required_fields"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), payload.StoreID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	payload.PaymentMethod = strings.TrimSpace(payload.PaymentMethod)

	fulfillmentType, ok := normalizeFulfillmentType(w, payload.FulfillmentType)
	if !ok {
		return
	}
	if fulfillmentType == "delivery" && !validateDeliveryRequest(w, payload.Delivery) {
		return
	}

	if payload.IdempotencyKey != "" {
		existing, err := fetchIdempotentOrderForStore(
			ctx,
			firestoreClient,
			payload.IdempotencyKey,
			payload.StoreID,
			r.Context(),
			cfg.RequireAuth,
		)
		if err != nil {
			writeIdempotencyError(w, err)
			return
		}
		if existing != nil {
			writeJSON(w, http.StatusOK, existing)
			return
		}
	}

	isGasOrder := isGasStationBusinessType(payload.BusinessType)
	menu, err := fetchMenuCached(ctx, firestoreClient, payload.StoreID)
	if err != nil {
		log.Printf("failed fetching menu for order validation: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
		return
	}
	if menu == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "menu_not_found"})
		return
	}

	fuelRecord, totals, ok := normalizeOrderPayloadForCreate(w, menu, &payload, isGasOrder)
	if !ok {
		return
	}

	now := time.Now().UTC()
	expire := now.Add(time.Duration(cfg.OrderTTLDays) * 24 * time.Hour)

	order := orderRecord{
		ID:              generateOrderID(),
		StoreID:         payload.StoreID,
		CallSid:         payload.CallSid,
		Channel:         payload.Channel,
		CustomerName:    payload.CustomerName,
		TenantID:        payload.TenantID,
		CustomerID:      payload.CustomerID,
		CallerID:        payload.CallerID,
		ChannelContact:  payload.ChannelContact,
		Origin:          normalizeOrderOrigin(payload.Origin),
		Notes:           payload.Notes,
		BusinessType:    payload.BusinessType,
		PaymentMethod:   payload.PaymentMethod,
		Items:           payload.Items,
		Fuel:            fuelRecord,
		Status:          statusPending,
		FulfillmentType: fulfillmentType,
		Delivery:        payload.Delivery,
		SubtotalCents:   totals.SubtotalCents,
		TaxCents:        totals.TaxCents,
		FeeCents:        totals.FeeCents,
		DiscountCents:   totals.DiscountCents,
		TotalCents:      totals.TotalCents,
		CreatedAt:       now,
		UpdatedAt:       now,
		ExpireAt:        expire,
	}

	order, err = createOrderFn(ctx, firestoreClient, order, payload.IdempotencyKey)
	if err != nil {
		if errors.Is(err, errIdempotencyConflict) && payload.IdempotencyKey != "" {
			existing, fetchErr := fetchIdempotentOrderForStore(
				ctx,
				firestoreClient,
				payload.IdempotencyKey,
				payload.StoreID,
				r.Context(),
				cfg.RequireAuth,
			)
			if fetchErr == nil && existing != nil {
				writeJSON(w, http.StatusOK, existing)
				return
			}
			if fetchErr != nil {
				writeIdempotencyError(w, fetchErr)
				return
			}
		}
		log.Printf("failed to create order: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_creation_failed"})
		return
	}
	atomic.AddUint64(&ordersCreatedCounter, 1)

	if pubsubClient != nil && cfg.OrdersTopic != "" {
		if err := publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, order); err != nil {
			log.Printf("failed to publish order event: %v", err)
		}
	}

	log.Printf("created order %s for call %s", order.ID, order.CallSid)
	writeJSON(w, http.StatusAccepted, order)
}

func normalizeFulfillmentType(w http.ResponseWriter, raw string) (string, bool) {
	fulfillmentType := strings.ToLower(strings.TrimSpace(raw))
	if fulfillmentType == "" {
		fulfillmentType = "pickup"
	}
	if fulfillmentType != "pickup" && fulfillmentType != "delivery" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_fulfillment_type"})
		return "", false
	}
	return fulfillmentType, true
}

func validateDeliveryRequest(w http.ResponseWriter, delivery *orderDelivery) bool {
	if delivery == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_delivery"})
		return false
	}
	delivery.FleetMode = strings.ToLower(strings.TrimSpace(delivery.FleetMode))
	if delivery.FleetMode != "owned_fleet" &&
		delivery.FleetMode != "third_party" &&
		delivery.FleetMode != "marketplace" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_delivery_fleet_mode"})
		return false
	}
	hasLatLng := delivery.DropoffLatLng != nil &&
		delivery.DropoffLatLng.Lat != 0 &&
		delivery.DropoffLatLng.Lng != 0
	hasAddress := false
	if delivery.DropoffAddress != nil {
		a := delivery.DropoffAddress
		hasAddress = strings.TrimSpace(a.Formatted) != "" ||
			strings.TrimSpace(a.Line1) != "" ||
			strings.TrimSpace(a.City) != ""
	}
	if !hasLatLng && !hasAddress {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_dropoff"})
		return false
	}
	return true
}

func normalizeOrderPayloadForCreate(
	w http.ResponseWriter,
	menu *menuRecord,
	payload *orderRequest,
	isGasOrder bool,
) (*fuelOrder, totals, bool) {
	if isGasOrder {
		if strings.TrimSpace(payload.PaymentMethod) == "" {
			payload.PaymentMethod = "card"
		}
		if strings.ToLower(strings.TrimSpace(payload.PaymentMethod)) != "card" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "gas_card_only"})
			return nil, totals{}, false
		}
		if payload.Fuel == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fuel"})
			return nil, totals{}, false
		}
		fuel, fuelTotals, err := normalizeFuelOrder(*menu, *payload.Fuel)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return nil, totals{}, false
		}
		payload.Items = []orderItem{}
		return &fuel, fuelTotals, true
	}

	normalizedItems, draftErrs := validateOrderDraftAgainstMenu(*menu, payload.Items)
	if draftErrs != nil && !isEmptyDraftErrors(*draftErrs) {
		writeJSON(
			w,
			http.StatusBadRequest,
			validateOrderDraftResponse{
				OK:              false,
				MenuVersion:     menu.UpdatedAt.Format(time.RFC3339),
				NormalizedItems: normalizedItems,
				Errors:          draftErrs,
			},
		)
		return nil, totals{}, false
	}
	payload.Items = normalizedItems
	return nil, computeTotals(*payload), true
}
