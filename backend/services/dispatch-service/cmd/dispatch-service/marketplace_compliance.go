package main

import (
	"context"
	"fmt"

	cloudfirestore "cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	deliveryPartnerComplianceCollection = "delivery_partner_compliance"
	deliveryPartnerStripeCollection     = "delivery_partner_stripe"
)

type deliveryPartnerStripeDoc struct {
	Stripe struct {
		Status          string `firestore:"status"`
		PayoutsEnabled  bool   `firestore:"payouts_enabled"`
		DetailsSubmitted bool  `firestore:"details_submitted"`
	} `firestore:"stripe"`
}

type deliveryPartnerComplianceDocument struct {
	Status string `firestore:"status"`
}

type deliveryPartnerComplianceDoc struct {
	Status       string                               `firestore:"status"`
	RequiredDocs []string                             `firestore:"required_docs"`
	Documents    map[string]deliveryPartnerComplianceDocument `firestore:"documents"`
}

type delivererEligibility struct {
	StripeReady     bool     `json:"stripeReady"`
	ComplianceReady bool     `json:"complianceReady"`
	StripeStatus    string   `json:"stripeStatus,omitempty"`
	ComplianceStatus string  `json:"complianceStatus,omitempty"`
	MissingDocs     []string `json:"missingDocs,omitempty"`
}

func fetchDeliveryPartnerStripe(ctx context.Context, fs *cloudfirestore.Client, delivererID string) (*deliveryPartnerStripeDoc, error) {
	if fs == nil {
		return nil, fmt.Errorf("firestore_not_configured")
	}
	doc, err := fs.Collection(deliveryPartnerStripeCollection).Doc(delivererID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var record deliveryPartnerStripeDoc
	if err := doc.DataTo(&record); err != nil {
		return nil, err
	}
	return &record, nil
}

func fetchDeliveryPartnerCompliance(ctx context.Context, fs *cloudfirestore.Client, delivererID string) (*deliveryPartnerComplianceDoc, error) {
	if fs == nil {
		return nil, fmt.Errorf("firestore_not_configured")
	}
	doc, err := fs.Collection(deliveryPartnerComplianceCollection).Doc(delivererID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil
		}
		return nil, err
	}
	var record deliveryPartnerComplianceDoc
	if err := doc.DataTo(&record); err != nil {
		return nil, err
	}
	return &record, nil
}

func complianceMissingDocs(record *deliveryPartnerComplianceDoc) []string {
	if record == nil || len(record.RequiredDocs) == 0 {
		return []string{}
	}
	out := []string{}
	for _, doc := range record.RequiredDocs {
		entry, ok := record.Documents[doc]
		if !ok || entry.Status == "rejected" {
			out = append(out, doc)
		}
	}
	return out
}

func ensureDelivererEligible(ctx context.Context, fs *cloudfirestore.Client, delivererID string) (bool, delivererEligibility, error) {
	eligibility := delivererEligibility{}
	stripeDoc, err := fetchDeliveryPartnerStripe(ctx, fs, delivererID)
	if err != nil {
		return false, eligibility, err
	}
	if stripeDoc != nil {
		eligibility.StripeStatus = stripeDoc.Stripe.Status
		eligibility.StripeReady = stripeDoc.Stripe.PayoutsEnabled && stripeDoc.Stripe.DetailsSubmitted
	}

	complianceDoc, err := fetchDeliveryPartnerCompliance(ctx, fs, delivererID)
	if err != nil {
		return false, eligibility, err
	}
	if complianceDoc != nil {
		eligibility.ComplianceStatus = complianceDoc.Status
		eligibility.MissingDocs = complianceMissingDocs(complianceDoc)
		eligibility.ComplianceReady = complianceDoc.Status == "approved" && len(eligibility.MissingDocs) == 0
	}

	ready := eligibility.StripeReady && eligibility.ComplianceReady
	return ready, eligibility, nil
}
