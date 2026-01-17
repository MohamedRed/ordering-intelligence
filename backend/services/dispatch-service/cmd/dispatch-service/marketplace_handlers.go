package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"golang.org/x/oauth2"
)

func handleMarketplaceDelivererRegister(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var payload struct {
		DisplayName string `json:"displayName"`
		PhoneE164   string `json:"phoneE164"`
	}
	_ = json.NewDecoder(r.Body).Decode(&payload)
	now := time.Now().UTC()
	record, _ := fetchMarketplaceDeliverer(r.Context(), fs, uid)
	if record == nil {
		record = &marketplaceDeliverer{
			DelivererID: uid,
			Active:      true,
			Available:   true,
			Status:      marketplaceDelivererStatusAvailable,
			CreatedAt:   now,
		}
	}
	if strings.TrimSpace(payload.DisplayName) != "" {
		record.DisplayName = strings.TrimSpace(payload.DisplayName)
	}
	if strings.TrimSpace(payload.PhoneE164) != "" {
		record.PhoneE164 = strings.TrimSpace(payload.PhoneE164)
	}
	record.Active = true
	record.Available = true
	record.Status = marketplaceDelivererStatusAvailable
	record.UpdatedAt = now
	eligible, _, err := ensureDelivererEligible(r.Context(), fs, uid)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_eligibility_failed"})
		return
	}
	if !eligible {
		record.Available = false
		record.Status = marketplaceDelivererStatusUnavailable
	}
	if err := upsertMarketplaceDeliverer(r.Context(), fs, *record); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func handleMarketplaceAvailability(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var payload struct {
		Available bool `json:"available"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if payload.Available {
		eligible, eligibility, err := ensureDelivererEligible(r.Context(), fs, uid)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_eligibility_failed"})
			return
		}
		if !eligible {
			writeJSON(w, http.StatusForbidden, map[string]any{"error": "deliverer_not_ready", "eligibility": eligibility})
			return
		}
	}
	record, err := fetchMarketplaceDeliverer(r.Context(), fs, uid)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_fetch_failed"})
		return
	}
	if record == nil {
		record = &marketplaceDeliverer{DelivererID: uid, Active: true}
	}
	record.Available = payload.Available
	record.Active = true
	record.Status = marketplaceDelivererStatusUnavailable
	if record.Available {
		record.Status = marketplaceDelivererStatusAvailable
	}
	record.UpdatedAt = time.Now().UTC()
	if err := upsertMarketplaceDeliverer(r.Context(), fs, *record); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func handleMarketplaceLocation(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var payload struct {
		Lat       float64 `json:"lat"`
		Lng       float64 `json:"lng"`
		AccuracyM float64 `json:"accuracyM"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	if payload.Lat == 0 || payload.Lng == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_location"})
		return
	}
	record, err := updateMarketplaceDelivererLocation(r.Context(), fs, uid, payload.Lat, payload.Lng, payload.AccuracyM)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "location_update_failed"})
		return
	}
	writeJSON(w, http.StatusOK, record)
}

func handleMarketplaceOffersList(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	statuses := []string{}
	if status != "" {
		statuses = append(statuses, status)
	} else {
		statuses = []string{
			marketplaceOfferStatusOpen,
			marketplaceOfferStatusAssigned,
			marketplaceOfferStatusPrewarm,
		}
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	offers, err := listMarketplaceOffersForDeliverer(ctx, fs, uid, statuses, 50)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "offer_fetch_failed"})
		return
	}
	out := make([]marketplaceOfferView, 0, len(offers))
	for _, offer := range offers {
		out = append(out, marketplaceOfferView{
			OfferID:             offer.OfferID,
			OrderID:             offer.OrderID,
			StoreID:             offer.StoreID,
			Status:              offer.Status,
			PayoutCents:         offer.PayoutCents,
			Currency:            offer.Currency,
			DropoffLatLng:       offer.DropoffLatLng,
			DropoffAddress:      offer.DropoffAddress,
			Instructions:        offer.Instructions,
			SelectedDelivererID: offer.SelectedDeliverer,
			ExpiresAt:           offer.ExpiresAt.UTC().Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"offers": out})
}

func handleMarketplaceOfferAccept(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	offerID string,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	offer, err := fetchMarketplaceOffer(ctx, fs, offerID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "offer_fetch_failed"})
		return
	}
	if offer == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "offer_not_found"})
		return
	}
	if offer.Status != marketplaceOfferStatusOpen {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "offer_closed"})
		return
	}
	if !containsString(offer.CandidateIDs, uid) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not_candidate"})
		return
	}
	deliverer, err := fetchMarketplaceDeliverer(ctx, fs, uid)
	if err != nil || deliverer == nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "deliverer_not_found"})
		return
	}
	eligible, eligibility, err := ensureDelivererEligible(ctx, fs, uid)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "deliverer_eligibility_failed"})
		return
	}
	if !eligible {
		writeJSON(w, http.StatusForbidden, map[string]any{"error": "deliverer_not_ready", "eligibility": eligibility})
		return
	}
	if deliverer.CurrentOrderID != "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "already_assigned"})
		return
	}

	dist := 0.0
	if offer.DropoffLatLng != nil {
		dist = haversineMeters(deliverer.Lat, deliverer.Lng, offer.DropoffLatLng.Lat, offer.DropoffLatLng.Lng)
	}
	score := scoreMarketplaceDistance(*deliverer, dist, time.Now().UTC())

	acceptance := marketplaceOfferAcceptance{
		DelivererID:    uid,
		AcceptedAt:     time.Now().UTC(),
		DistanceMeters: dist,
		Score:          score,
	}

	offerRef := fs.Collection(marketplaceOffersCollection).Doc(offerID)
	accRef := offerRef.Collection(marketplaceOfferAcceptancesSubcollection).Doc(uid)

	err = fs.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		snap, err := tx.Get(offerRef)
		if err != nil {
			return err
		}
		var current marketplaceOffer
		if err := snap.DataTo(&current); err != nil {
			return err
		}
		if current.Status != marketplaceOfferStatusOpen {
			return fmt.Errorf("offer_closed")
		}
		if !containsString(current.CandidateIDs, uid) {
			return fmt.Errorf("not_candidate")
		}
		if accSnap, err := tx.Get(accRef); err == nil && accSnap.Exists() {
			return nil
		}
		if err := tx.Set(accRef, acceptance); err != nil {
			return err
		}
		updates := []cloudfirestore.Update{
			{Path: "acceptedCount", Value: current.AcceptedCount + 1},
			{Path: "updatedAt", Value: time.Now().UTC()},
		}
		return tx.Update(offerRef, updates)
	})
	if err != nil {
		if strings.Contains(err.Error(), "offer_closed") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "offer_closed"})
			return
		}
		if strings.Contains(err.Error(), "not_candidate") {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "not_candidate"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "accept_failed"})
		return
	}

	deliverer.LastOfferAt = time.Now().UTC()
	_ = upsertMarketplaceDeliverer(ctx, fs, *deliverer)

	writeJSON(w, http.StatusOK, map[string]string{"status": "accepted"})
}

func handleMarketplaceOrderStatus(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	httpClient *http.Client,
	orderTokenSrc oauth2.TokenSource,
	orderID string,
) {
	uid := authUID(r.Context())
	if uid == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var payload struct {
		Status  string `json:"status"`
		OfferID string `json:"offerId"`
		StoreID string `json:"storeId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	status := strings.ToLower(strings.TrimSpace(payload.Status))
	if status == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_status"})
		return
	}
	storeID := strings.TrimSpace(payload.StoreID)
	if storeID == "" && payload.OfferID != "" {
		if offer, _ := fetchMarketplaceOffer(r.Context(), fs, payload.OfferID); offer != nil {
			storeID = offer.StoreID
		}
	}
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}

	deliveryStatus := status
	assignmentStatus := status
	switch status {
	case "picked_up":
		assignmentStatus = "assigned"
		deliveryStatus = "picked_up"
	case "out_for_delivery":
		assignmentStatus = "assigned"
		deliveryStatus = "out_for_delivery"
	case "delivered":
		assignmentStatus = "completed"
		deliveryStatus = "delivered"
	}

	_ = patchOrderDelivery(r.Context(), httpClient, orderTokenSrc, cfg.OrderServiceURL, orderID, map[string]any{
		"assignedDriverId":      uid,
		"assignmentStatus":      assignmentStatus,
		"deliveryStatusSummary": deliveryStatus,
	})

	_ = publishDispatchEvent(r.Context(), pubsubClient, cfg, dispatchEvent{
		Kind:      deliveryStatus,
		StoreID:   storeID,
		OrderID:   orderID,
		DriverID:  uid,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	})

	if status == "delivered" {
		if deliverer, err := fetchMarketplaceDeliverer(r.Context(), fs, uid); err == nil && deliverer != nil {
			deliverer.LastDeliveryAt = time.Now().UTC()
			deliverer.CurrentOrderID = ""
			deliverer.Available = true
			deliverer.Status = marketplaceDelivererStatusAvailable
			_ = upsertMarketplaceDeliverer(r.Context(), fs, *deliverer)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleMarketplacePrewarm(
	w http.ResponseWriter,
	r *http.Request,
	fs *cloudfirestore.Client,
	cfg *serviceConfig,
	pubsubClient *cloudpubsub.Client,
	storeID string,
) {
	var payload struct {
		DropoffLatLng  *deliveryLatLng  `json:"dropoffLatLng"`
		DropoffAddress *deliveryAddress `json:"dropoffAddress"`
		DropoffQuery   string           `json:"dropoffAddressText"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	storeLoc, err := fetchStoreLocation(ctx, fs, storeID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	drop, addr, err := resolveDropoff(ctx, cfg, payload.DropoffLatLng, payload.DropoffAddress, payload.DropoffQuery)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	candidates, err := prewarmMarketplaceOffer(ctx, fs, cfg, pubsubClient, storeID, storeLoc, drop, addr)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "prewarm_failed"})
		return
	}
	etaMinutes := 0
	if cfg.RadarAPIKey != "" {
		if secs, err := radarDurationSeconds(ctx, cfg.RadarAPIKey, storeLoc.Lat, storeLoc.Lng, drop.Lat, drop.Lng); err == nil {
			etaMinutes = int(math.Round(secs / 60.0))
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"candidateIds":   candidates,
		"dropoffLatLng":  drop,
		"dropoffAddress": addr,
		"etaMinutes":     etaMinutes,
	})
}

func resolveDropoff(
	ctx context.Context,
	cfg *serviceConfig,
	latlng *deliveryLatLng,
	addr *deliveryAddress,
	query string,
) (*deliveryLatLng, *deliveryAddress, error) {
	if latlng != nil && latlng.Lat != 0 && latlng.Lng != 0 {
		return latlng, addr, nil
	}
	q := strings.TrimSpace(query)
	if q == "" && addr != nil {
		q = strings.TrimSpace(firstNonEmpty(
			addr.Formatted,
			strings.TrimSpace(addr.Line1+" "+addr.City+" "+addr.State+" "+addr.PostalCode),
		))
	}
	if q == "" {
		return nil, addr, fmt.Errorf("missing_dropoff")
	}
	if strings.TrimSpace(cfg.RadarAPIKey) == "" {
		return nil, addr, fmt.Errorf("radar_not_configured")
	}
	lat, lng, formatted, err := radarForwardGeocode(ctx, cfg.RadarAPIKey, q)
	if err != nil {
		return nil, addr, fmt.Errorf("geocode_unavailable")
	}
	if addr == nil {
		addr = &deliveryAddress{}
	}
	if strings.TrimSpace(addr.Formatted) == "" {
		addr.Formatted = formatted
	}
	return &deliveryLatLng{Lat: lat, Lng: lng}, addr, nil
}

func containsString(values []string, target string) bool {
	for _, v := range values {
		if v == target {
			return true
		}
	}
	return false
}
