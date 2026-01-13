package main

import (
	"strings"
	"time"
)

func groupOrderPricingForSubmit(session groupOrderSession) groupOrderPricing {
	pricing := session.Pricing
	if pricing.TotalCents == 0 {
		totals := computeTotals(orderRequest{
			Items:         session.Items,
			TaxCents:      pricing.TaxCents,
			FeeCents:      pricing.FeeCents,
			DiscountCents: pricing.DiscountCents,
		})
		pricing = groupOrderPricing{
			SubtotalCents: totals.SubtotalCents,
			TaxCents:      totals.TaxCents,
			FeeCents:      totals.FeeCents,
			DiscountCents: totals.DiscountCents,
			TotalCents:    totals.TotalCents,
			Allocations:   session.Pricing.Allocations,
		}
	}
	return pricing
}

func orderRecordFromGroup(session groupOrderSession, pricing groupOrderPricing, ttlDays int) orderRecord {
	now := time.Now().UTC()
	expire := now.Add(time.Duration(ttlDays) * 24 * time.Hour)
	return orderRecord{
		ID:              generateOrderID(),
		StoreID:         session.StoreID,
		Channel:         "group_order",
		CustomerName:    strings.TrimSpace(session.Host.DisplayName),
		TenantID:        session.TenantID,
		CustomerID:      strings.TrimSpace(session.CustomerID),
		CallerID:        strings.TrimSpace(session.Host.UserID),
		ChannelContact:  &session.Host,
		Items:           session.Items,
		Status:          statusPending,
		FulfillmentType: session.FulfillmentType,
		Delivery:        session.Delivery,
		SubtotalCents:   pricing.SubtotalCents,
		TaxCents:        pricing.TaxCents,
		FeeCents:        pricing.FeeCents,
		DiscountCents:   pricing.DiscountCents,
		TotalCents:      pricing.TotalCents,
		CreatedAt:       now,
		UpdatedAt:       now,
		ExpireAt:        expire,
	}
}
