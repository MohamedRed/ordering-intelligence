package main

import "time"

const (
	marketplaceDeliverersCollection            = "marketplace_deliverers"
	marketplaceOffersCollection                = "marketplace_offers"
	marketplaceOfferAcceptancesSubcollection   = "acceptances"
	marketplaceOfferStatusOpen                 = "open"
	marketplaceOfferStatusPrewarm              = "prewarm"
	marketplaceOfferStatusAssigned             = "assigned"
	marketplaceOfferStatusExpired              = "expired"
	marketplaceDelivererStatusAvailable        = "available"
	marketplaceDelivererStatusUnavailable      = "unavailable"
	marketplaceDefaultCurrency                 = "USD"
	marketplaceDefaultInitialRadiusMeters      = 1000
	marketplaceDefaultExpandRadiusMeters       = 400
	marketplaceDefaultMaxRadiusMeters          = 2400
	marketplaceDefaultOfferTTLSeconds          = 30
	marketplaceDefaultPrewarmTTLSeconds        = 180
	marketplaceDefaultCandidateLimit           = 25
	marketplaceDefaultFairnessBoostMetersPerHr = 300
)

type marketplaceDeliverer struct {
	DelivererID       string    `json:"delivererId" firestore:"delivererId"`
	DisplayName       string    `json:"displayName,omitempty" firestore:"displayName,omitempty"`
	PhoneE164         string    `json:"phoneE164,omitempty" firestore:"phoneE164,omitempty"`
	Status            string    `json:"status,omitempty" firestore:"status,omitempty"`
	Active            bool      `json:"active" firestore:"active"`
	Available         bool      `json:"available" firestore:"available"`
	Lat               float64   `json:"lat,omitempty" firestore:"lat,omitempty"`
	Lng               float64   `json:"lng,omitempty" firestore:"lng,omitempty"`
	AccuracyM         float64   `json:"accuracyM,omitempty" firestore:"accuracyM,omitempty"`
	LastLocationAt    time.Time `json:"lastLocationAt,omitempty" firestore:"lastLocationAt,omitempty"`
	LocationExpiresAt time.Time `json:"locationExpiresAt,omitempty" firestore:"locationExpiresAt,omitempty"`
	LastOfferAt       time.Time `json:"lastOfferAt,omitempty" firestore:"lastOfferAt,omitempty"`
	LastDeliveryAt    time.Time `json:"lastDeliveryAt,omitempty" firestore:"lastDeliveryAt,omitempty"`
	CurrentOrderID    string    `json:"currentOrderId,omitempty" firestore:"currentOrderId,omitempty"`
	CreatedAt         time.Time `json:"createdAt" firestore:"createdAt"`
	UpdatedAt         time.Time `json:"updatedAt" firestore:"updatedAt"`
}

type marketplaceOffer struct {
	OfferID           string           `json:"offerId" firestore:"offerId"`
	OrderID           string           `json:"orderId,omitempty" firestore:"orderId,omitempty"`
	StoreID           string           `json:"storeId" firestore:"storeId"`
	Status            string           `json:"status" firestore:"status"`
	PayoutCents       int64            `json:"payoutCents" firestore:"payoutCents"`
	Currency          string           `json:"currency" firestore:"currency"`
	DropoffLatLng     *deliveryLatLng  `json:"dropoffLatLng,omitempty" firestore:"dropoffLatLng,omitempty"`
	DropoffAddress    *deliveryAddress `json:"dropoffAddress,omitempty" firestore:"dropoffAddress,omitempty"`
	Instructions      string           `json:"instructions,omitempty" firestore:"instructions,omitempty"`
	CandidateIDs      []string         `json:"candidateIds,omitempty" firestore:"candidateIds,omitempty"`
	SelectedDeliverer string           `json:"selectedDelivererId,omitempty" firestore:"selectedDelivererId,omitempty"`
	AcceptedCount     int              `json:"acceptedCount,omitempty" firestore:"acceptedCount,omitempty"`
	ExpiresAt         time.Time        `json:"expiresAt" firestore:"expiresAt"`
	CreatedAt         time.Time        `json:"createdAt" firestore:"createdAt"`
	UpdatedAt         time.Time        `json:"updatedAt" firestore:"updatedAt"`
}

type marketplaceOfferAcceptance struct {
	DelivererID    string    `json:"delivererId" firestore:"delivererId"`
	AcceptedAt     time.Time `json:"acceptedAt" firestore:"acceptedAt"`
	DistanceMeters float64   `json:"distanceMeters,omitempty" firestore:"distanceMeters,omitempty"`
	FairnessScore  float64   `json:"fairnessScore,omitempty" firestore:"fairnessScore,omitempty"`
	Score          float64   `json:"score,omitempty" firestore:"score,omitempty"`
}

type marketplaceOfferView struct {
	OfferID             string           `json:"offerId"`
	OrderID             string           `json:"orderId,omitempty"`
	StoreID             string           `json:"storeId"`
	Status              string           `json:"status"`
	PayoutCents         int64            `json:"payoutCents"`
	Currency            string           `json:"currency"`
	DropoffLatLng       *deliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress      *deliveryAddress `json:"dropoffAddress,omitempty"`
	Instructions        string           `json:"instructions,omitempty"`
	SelectedDelivererID string           `json:"selectedDelivererId,omitempty"`
	ExpiresAt           string           `json:"expiresAt"`
}
