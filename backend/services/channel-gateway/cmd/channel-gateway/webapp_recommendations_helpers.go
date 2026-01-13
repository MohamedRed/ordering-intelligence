package main

import (
	"strings"
	"time"
)

const reordersCollection = "customer_reorders"

type reorderItem struct {
	ItemID    string            `json:"itemId" firestore:"itemId"`
	Name      string            `json:"name" firestore:"name"`
	Quantity  int               `json:"quantity" firestore:"quantity"`
	Category  string            `json:"category" firestore:"category"`
	Modifiers []reorderModifier `json:"modifiers" firestore:"modifiers"`
}

type reorderModifier struct {
	Name       string `json:"name" firestore:"name"`
	PriceCents int64  `json:"priceCents" firestore:"priceCents"`
}

type reorderTemplate struct {
	OrderTemplateID string        `json:"orderTemplateId" firestore:"orderTemplateId"`
	Title           string        `json:"title" firestore:"title"`
	Items           []reorderItem `json:"items" firestore:"items"`
	Fuel            *reorderFuel  `json:"fuel,omitempty" firestore:"fuel,omitempty"`
	LastOrderedAt   time.Time     `json:"lastOrderedAt" firestore:"lastOrderedAt"`
}

type reorderDoc struct {
	StoreID     string            `json:"storeId" firestore:"storeId"`
	CustomerID  string            `json:"customerId" firestore:"customerId"`
	TopReorders []reorderTemplate `json:"topReorders" firestore:"topReorders"`
}

type reorderFuel struct {
	FuelGradeID          string  `json:"fuelGradeId" firestore:"fuelGradeId"`
	FuelGradeName        string  `json:"fuelGradeName,omitempty" firestore:"fuelGradeName,omitempty"`
	Unit                 string  `json:"unit,omitempty" firestore:"unit,omitempty"`
	UnitPriceCents       int64   `json:"unitPriceCents,omitempty" firestore:"unitPriceCents,omitempty"`
	RequestedLiters      float64 `json:"requestedLiters,omitempty" firestore:"requestedLiters,omitempty"`
	RequestedAmountCents int64   `json:"requestedAmountCents,omitempty" firestore:"requestedAmountCents,omitempty"`
	PreauthAmountCents   int64   `json:"preauthAmountCents,omitempty" firestore:"preauthAmountCents,omitempty"`
	PaymentFlow          string  `json:"paymentFlow,omitempty" firestore:"paymentFlow,omitempty"`
	PumpNumber           string  `json:"pumpNumber,omitempty" firestore:"pumpNumber,omitempty"`
}

type webAppReorder struct {
	StoreID      string        `json:"storeId"`
	StoreName    string        `json:"storeName"`
	TenantID     string        `json:"tenantId"`
	BusinessType string        `json:"businessType"`
	LogoURL      string        `json:"logoUrl"`
	Currency     string        `json:"currency,omitempty"`
	Title        string        `json:"title"`
	ItemCount    int           `json:"itemCount"`
	OrderedAt    string        `json:"orderedAt"`
	Items        []reorderItem `json:"items,omitempty"`
	Fuel         *reorderFuel  `json:"fuel,omitempty"`
}

func toWebAppReorder(t reorderTemplate, meta storeMetadata) webAppReorder {
	orderedAt := ""
	if !t.LastOrderedAt.IsZero() {
		orderedAt = t.LastOrderedAt.UTC().Format(time.RFC3339)
	}
	return webAppReorder{
		StoreID:      meta.StoreID,
		StoreName:    meta.StoreName,
		TenantID:     meta.TenantID,
		BusinessType: meta.BusinessType,
		LogoURL:      meta.LogoURL,
		Currency:     meta.Currency,
		Title:        strings.TrimSpace(t.Title),
		ItemCount:    countReorderItems(t.Items, t.Fuel),
		OrderedAt:    orderedAt,
		Items:        t.Items,
		Fuel:         t.Fuel,
	}
}

func countReorderItems(items []reorderItem, fuel *reorderFuel) int {
	total := 0
	for _, item := range items {
		if item.Quantity > 0 {
			total += item.Quantity
		} else {
			total++
		}
	}
	if total == 0 && fuel != nil {
		total = 1
	}
	return total
}
