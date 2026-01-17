package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const draftTTL = 7 * 24 * time.Hour

type webAppDraftPayload struct {
	SessionID       string               `json:"sessionId"`
	StoreID         string               `json:"storeId"`
	OrderType       string               `json:"orderType"`
	GroupOrderID    string               `json:"groupOrderId,omitempty"`
	FulfillmentType string               `json:"fulfillmentType,omitempty"`
	Notes           string               `json:"notes,omitempty"`
	Items           []webAppDraftItem    `json:"items"`
	Delivery        *webAppDraftDelivery `json:"delivery,omitempty"`
	Version         int                  `json:"version,omitempty"`
}

type webAppDraftItem struct {
	ItemID     string                `json:"itemId" firestore:"item_id"`
	Name       string                `json:"name" firestore:"name"`
	PriceCents int                   `json:"priceCents" firestore:"price_cents"`
	Quantity   int                   `json:"quantity" firestore:"quantity"`
	Modifiers  []webAppDraftModifier `json:"modifiers" firestore:"modifiers"`
}

type webAppDraftModifier struct {
	GroupID    string `json:"groupId" firestore:"group_id"`
	OptionID   string `json:"optionId" firestore:"option_id"`
	Name       string `json:"name" firestore:"name"`
	PriceCents int    `json:"priceCents" firestore:"price_cents"`
}

type webAppDraftDelivery struct {
	AddressText    string         `json:"addressText" firestore:"address_text"`
	Instructions   string         `json:"instructions" firestore:"instructions"`
	DropoffLatLng  *webAppLatLng  `json:"dropoffLatLng,omitempty" firestore:"dropoff_lat_lng,omitempty"`
	DropoffAddress *webAppAddress `json:"dropoffAddress,omitempty" firestore:"dropoff_address,omitempty"`
}

type webAppLatLng struct {
	Lat float64 `json:"lat" firestore:"lat"`
	Lng float64 `json:"lng" firestore:"lng"`
}

type webAppAddress struct {
	Line1      string `json:"line1" firestore:"line1"`
	Line2      string `json:"line2" firestore:"line2"`
	City       string `json:"city" firestore:"city"`
	State      string `json:"state" firestore:"state"`
	PostalCode string `json:"postalCode" firestore:"postal_code"`
	Country    string `json:"country" firestore:"country"`
	Formatted  string `json:"formatted" firestore:"formatted"`
}

type webAppDraftRecord struct {
	ID              string               `json:"id" firestore:"id"`
	CustomerID      string               `json:"customerId" firestore:"customer_id"`
	StoreID         string               `json:"storeId" firestore:"store_id"`
	OrderType       string               `json:"orderType" firestore:"order_type"`
	GroupOrderID    string               `json:"groupOrderId,omitempty" firestore:"group_order_id,omitempty"`
	FulfillmentType string               `json:"fulfillmentType" firestore:"fulfillment_type"`
	Notes           string               `json:"notes,omitempty" firestore:"notes,omitempty"`
	Items           []webAppDraftItem    `json:"items" firestore:"items"`
	Delivery        *webAppDraftDelivery `json:"delivery,omitempty" firestore:"delivery,omitempty"`
	Version         int                  `json:"version" firestore:"version"`
	CreatedAt       time.Time            `json:"createdAt" firestore:"created_at"`
	UpdatedAt       time.Time            `json:"updatedAt" firestore:"updated_at"`
	ExpiresAt       time.Time            `json:"expiresAt" firestore:"expires_at"`
}

var errDraftConflict = errors.New("draft_version_conflict")

func handleWebAppDraftGet(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	storeID := strings.TrimSpace(r.URL.Query().Get("storeId"))
	orderType := strings.TrimSpace(r.URL.Query().Get("orderType"))
	groupOrderID := strings.TrimSpace(r.URL.Query().Get("groupOrderId"))
	if sessionID == "" || storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_store"})
		return
	}
	if orderType == "" {
		orderType = "single"
	}
	if orderType == "group" && groupOrderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, client, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusOK, map[string]any{"draft": nil})
		return
	}
	docID := draftDocID(session.CustomerID, storeID, orderType, groupOrderID)
	snap, err := client.Collection(orderDraftsCollection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			writeJSON(w, http.StatusOK, map[string]any{"draft": nil})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "draft_fetch_failed"})
		return
	}
	var draft webAppDraftRecord
	if err := snap.DataTo(&draft); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "draft_decode_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"draft": draft})
}

func handleWebAppDraftUpsert(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	var payload webAppDraftPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.OrderType = strings.TrimSpace(payload.OrderType)
	payload.GroupOrderID = strings.TrimSpace(payload.GroupOrderID)
	if payload.SessionID == "" || payload.StoreID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_store"})
		return
	}
	if payload.OrderType == "" {
		payload.OrderType = "single"
	}
	if payload.OrderType == "group" && payload.GroupOrderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, client, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "customer_missing"})
		return
	}
	if !draftPayloadHasData(payload) {
		deleteDraft(ctx, client, session.CustomerID, payload.StoreID, payload.OrderType, payload.GroupOrderID)
		writeJSON(w, http.StatusOK, map[string]any{"draft": nil})
		return
	}
	now := time.Now().UTC()
	docID := draftDocID(session.CustomerID, payload.StoreID, payload.OrderType, payload.GroupOrderID)
	docRef := client.Collection(orderDraftsCollection).Doc(docID)
	var current webAppDraftRecord
	var latest webAppDraftRecord
	err = client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(docRef)
		if err != nil {
			if status.Code(err) != codes.NotFound {
				return err
			}
		}
		var existingVersion int
		createdAt := now
		if err == nil {
			if decodeErr := snap.DataTo(&current); decodeErr != nil {
				return decodeErr
			}
			existingVersion = current.Version
			createdAt = current.CreatedAt
			latest = current
		}
		if payload.Version > 0 && payload.Version != existingVersion {
			return errDraftConflict
		}
		nextVersion := existingVersion + 1
		record := webAppDraftRecord{
			ID:              docID,
			CustomerID:      session.CustomerID,
			StoreID:         payload.StoreID,
			OrderType:       payload.OrderType,
			GroupOrderID:    payload.GroupOrderID,
			FulfillmentType: normalizeFulfillment(payload.FulfillmentType),
			Notes:           strings.TrimSpace(payload.Notes),
			Items:           payload.Items,
			Delivery:        payload.Delivery,
			Version:         nextVersion,
			CreatedAt:       createdAt,
			UpdatedAt:       now,
			ExpiresAt:       now.Add(draftTTL),
		}
		latest = record
		return tx.Set(docRef, record)
	})
	if errors.Is(err, errDraftConflict) {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": "version_conflict",
			"draft": latest,
		})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "draft_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"draft": latest})
}

func handleWebAppDraftDelete(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
) {
	sessionID := strings.TrimSpace(r.URL.Query().Get("sessionId"))
	storeID := strings.TrimSpace(r.URL.Query().Get("storeId"))
	orderType := strings.TrimSpace(r.URL.Query().Get("orderType"))
	groupOrderID := strings.TrimSpace(r.URL.Query().Get("groupOrderId"))
	if sessionID == "" || storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session_or_store"})
		return
	}
	if orderType == "" {
		orderType = "single"
	}
	if orderType == "group" && groupOrderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, client, sessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
		return
	}
	deleteDraft(ctx, client, session.CustomerID, storeID, orderType, groupOrderID)
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func deleteDraft(
	ctx context.Context,
	client *cloudfirestore.Client,
	customerID string,
	storeID string,
	orderType string,
	groupOrderID string,
) {
	docID := draftDocID(customerID, storeID, orderType, groupOrderID)
	_ = client.Collection(orderDraftsCollection).Doc(docID).Delete(ctx)
}

func draftPayloadHasData(payload webAppDraftPayload) bool {
	if len(payload.Items) > 0 {
		return true
	}
	if strings.TrimSpace(payload.Notes) != "" {
		return true
	}
	if payload.Delivery == nil {
		return false
	}
	if strings.TrimSpace(payload.Delivery.AddressText) != "" {
		return true
	}
	if strings.TrimSpace(payload.Delivery.Instructions) != "" {
		return true
	}
	if payload.Delivery.DropoffAddress != nil || payload.Delivery.DropoffLatLng != nil {
		return true
	}
	return false
}

func normalizeFulfillment(value string) string {
	trimmed := strings.TrimSpace(strings.ToLower(value))
	if trimmed == "delivery" {
		return "delivery"
	}
	return "pickup"
}

func draftDocID(customerID, storeID, orderType, groupOrderID string) string {
	group := strings.TrimSpace(groupOrderID)
	if group == "" {
		group = "single"
	}
	return sanitizeDraftPart(customerID) + "__" + sanitizeDraftPart(storeID) + "__" + sanitizeDraftPart(orderType) + "__" + sanitizeDraftPart(group)
}

func sanitizeDraftPart(value string) string {
	clean := strings.TrimSpace(strings.ReplaceAll(value, "/", "_"))
	if clean == "" {
		return "none"
	}
	return clean
}
