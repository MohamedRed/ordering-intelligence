package main

import (
	"context"
	"fmt"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func fetchMarketplaceDeliverer(ctx context.Context, fs *cloudfirestore.Client, delivererID string) (*marketplaceDeliverer, error) {
	if fs == nil || delivererID == "" {
		return nil, fmt.Errorf("missing_deliverer")
	}
	doc, err := fs.Collection(marketplaceDeliverersCollection).Doc(delivererID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var record marketplaceDeliverer
	if err := doc.DataTo(&record); err != nil {
		return nil, err
	}
	if record.DelivererID == "" {
		record.DelivererID = delivererID
	}
	return &record, nil
}

func upsertMarketplaceDeliverer(ctx context.Context, fs *cloudfirestore.Client, record marketplaceDeliverer) error {
	if fs == nil || record.DelivererID == "" {
		return fmt.Errorf("missing_deliverer")
	}
	record.UpdatedAt = time.Now().UTC()
	if record.CreatedAt.IsZero() {
		record.CreatedAt = record.UpdatedAt
	}
	_, err := fs.Collection(marketplaceDeliverersCollection).Doc(record.DelivererID).Set(ctx, record)
	return err
}

func updateMarketplaceDelivererLocation(ctx context.Context, fs *cloudfirestore.Client, delivererID string, lat, lng, accuracy float64) (*marketplaceDeliverer, error) {
	now := time.Now().UTC()
	record, err := fetchMarketplaceDeliverer(ctx, fs, delivererID)
	if err != nil {
		return nil, err
	}
	if record == nil {
		record = &marketplaceDeliverer{
			DelivererID: delivererID,
			Active:      true,
			Available:   true,
			Status:      marketplaceDelivererStatusAvailable,
			CreatedAt:   now,
		}
	}
	record.Active = true
	record.Available = true
	record.Status = marketplaceDelivererStatusAvailable
	record.Lat = lat
	record.Lng = lng
	record.AccuracyM = accuracy
	record.LastLocationAt = now
	record.LocationExpiresAt = now.Add(5 * time.Minute)
	record.UpdatedAt = now
	if err := upsertMarketplaceDeliverer(ctx, fs, *record); err != nil {
		return nil, err
	}
	return record, nil
}

func listActiveMarketplaceDeliverers(ctx context.Context, fs *cloudfirestore.Client, limit int) ([]marketplaceDeliverer, error) {
	if fs == nil {
		return nil, fmt.Errorf("firestore_not_configured")
	}
	if limit <= 0 {
		limit = marketplaceDefaultCandidateLimit
	}
	now := time.Now().UTC()
	iter := fs.Collection(marketplaceDeliverersCollection).
		Where("active", "==", true).
		Where("available", "==", true).
		Where("locationExpiresAt", ">", now).
		Limit(limit).
		Documents(ctx)
	defer iter.Stop()

	out := []marketplaceDeliverer{}
	for {
		doc, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				break
			}
			return out, err
		}
		var record marketplaceDeliverer
		if err := doc.DataTo(&record); err != nil {
			continue
		}
		if record.DelivererID == "" {
			record.DelivererID = doc.Ref.ID
		}
		eligible, _, err := ensureDelivererEligible(ctx, fs, record.DelivererID)
		if err != nil {
			continue
		}
		if !eligible {
			continue
		}
		out = append(out, record)
	}
	return out, nil
}

func createMarketplaceOffer(ctx context.Context, fs *cloudfirestore.Client, offer marketplaceOffer) error {
	if fs == nil || offer.OfferID == "" {
		return fmt.Errorf("missing_offer")
	}
	offer.UpdatedAt = time.Now().UTC()
	if offer.CreatedAt.IsZero() {
		offer.CreatedAt = offer.UpdatedAt
	}
	_, err := fs.Collection(marketplaceOffersCollection).Doc(offer.OfferID).Set(ctx, offer)
	return err
}

func fetchMarketplaceOffer(ctx context.Context, fs *cloudfirestore.Client, offerID string) (*marketplaceOffer, error) {
	if fs == nil || offerID == "" {
		return nil, fmt.Errorf("missing_offer")
	}
	doc, err := fs.Collection(marketplaceOffersCollection).Doc(offerID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var offer marketplaceOffer
	if err := doc.DataTo(&offer); err != nil {
		return nil, err
	}
	if offer.OfferID == "" {
		offer.OfferID = offerID
	}
	return &offer, nil
}

func findMarketplaceOfferByOrderID(ctx context.Context, fs *cloudfirestore.Client, orderID string) (*marketplaceOffer, error) {
	if fs == nil || orderID == "" {
		return nil, fmt.Errorf("missing_order")
	}
	iter := fs.Collection(marketplaceOffersCollection).
		Where("orderId", "==", orderID).
		Limit(1).
		Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err != nil {
		if err == iterator.Done {
			return nil, nil
		}
		return nil, err
	}
	var offer marketplaceOffer
	if err := doc.DataTo(&offer); err != nil {
		return nil, err
	}
	if offer.OfferID == "" {
		offer.OfferID = doc.Ref.ID
	}
	return &offer, nil
}

func updateMarketplaceOffer(ctx context.Context, fs *cloudfirestore.Client, offer marketplaceOffer) error {
	if fs == nil || offer.OfferID == "" {
		return fmt.Errorf("missing_offer")
	}
	offer.UpdatedAt = time.Now().UTC()
	_, err := fs.Collection(marketplaceOffersCollection).Doc(offer.OfferID).Set(ctx, offer)
	return err
}

func listMarketplaceOffersForDeliverer(ctx context.Context, fs *cloudfirestore.Client, delivererID string, statuses []string, limit int) ([]marketplaceOffer, error) {
	if fs == nil || delivererID == "" {
		return nil, fmt.Errorf("missing_deliverer")
	}
	if limit <= 0 {
		limit = 25
	}
	query := fs.Collection(marketplaceOffersCollection).Where("candidateIds", "array-contains", delivererID)
	if len(statuses) > 0 {
		query = query.Where("status", "in", statuses)
	}
	iter := query.Limit(limit).Documents(ctx)
	defer iter.Stop()
	out := []marketplaceOffer{}
	for {
		doc, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				break
			}
			return out, err
		}
		var offer marketplaceOffer
		if err := doc.DataTo(&offer); err != nil {
			continue
		}
		if offer.OfferID == "" {
			offer.OfferID = doc.Ref.ID
		}
		out = append(out, offer)
	}
	return out, nil
}

func addMarketplaceAcceptance(ctx context.Context, fs *cloudfirestore.Client, offerID string, acceptance marketplaceOfferAcceptance) error {
	if fs == nil || offerID == "" || acceptance.DelivererID == "" {
		return fmt.Errorf("missing_acceptance")
	}
	ref := fs.Collection(marketplaceOffersCollection).Doc(offerID).Collection(marketplaceOfferAcceptancesSubcollection).Doc(acceptance.DelivererID)
	_, err := ref.Set(ctx, acceptance)
	return err
}

func listMarketplaceAcceptances(ctx context.Context, fs *cloudfirestore.Client, offerID string) ([]marketplaceOfferAcceptance, error) {
	if fs == nil || offerID == "" {
		return nil, fmt.Errorf("missing_offer")
	}
	iter := fs.Collection(marketplaceOffersCollection).Doc(offerID).Collection(marketplaceOfferAcceptancesSubcollection).Documents(ctx)
	defer iter.Stop()
	out := []marketplaceOfferAcceptance{}
	for {
		doc, err := iter.Next()
		if err != nil {
			if err == iterator.Done {
				break
			}
			return out, err
		}
		var acc marketplaceOfferAcceptance
		if err := doc.DataTo(&acc); err != nil {
			continue
		}
		if acc.DelivererID == "" {
			acc.DelivererID = doc.Ref.ID
		}
		out = append(out, acc)
	}
	return out, nil
}
