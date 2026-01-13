package main

import "time"

const groupOrdersCollection = "group_orders"

const (
	groupOrderStatusOpen           = "open"
	groupOrderStatusLocked         = "locked"
	groupOrderStatusPaymentPending = "payment_pending"
	groupOrderStatusPaid           = "paid"
	groupOrderStatusSubmitted      = "submitted"
	groupOrderStatusCancelled      = "cancelled"
	groupOrderStatusExpired        = "expired"
)

const (
	groupOrderPaymentSingle = "single_payer"
	groupOrderPaymentSplit  = "split_by_participant"
)

const (
	groupOrderPaymentMethodCash = "cash"
	groupOrderPaymentMethodCard = "card"
)

const (
	groupOrdersInvitesCollection = "invites"
	defaultInviteTTLMinutes      = 30
)

type groupOrderParticipant struct {
	ParticipantID string         `json:"participantId" firestore:"participantId"`
	Contact       channelContact `json:"channelContact" firestore:"channelContact"`
	DisplayName   string         `json:"displayName" firestore:"displayName"`
}

type groupOrderAllocation struct {
	ParticipantID string `json:"participantId" firestore:"participantId"`
	SubtotalCents int64  `json:"subtotalCents" firestore:"subtotalCents"`
	FeeCents      int64  `json:"feeCents" firestore:"feeCents"`
	TaxCents      int64  `json:"taxCents" firestore:"taxCents"`
	DiscountCents int64  `json:"discountCents" firestore:"discountCents"`
	TotalCents    int64  `json:"totalCents" firestore:"totalCents"`
}

type groupOrderPricing struct {
	SubtotalCents int64                  `json:"subtotalCents" firestore:"subtotalCents"`
	TaxCents      int64                  `json:"taxCents" firestore:"taxCents"`
	FeeCents      int64                  `json:"feeCents" firestore:"feeCents"`
	DiscountCents int64                  `json:"discountCents" firestore:"discountCents"`
	TotalCents    int64                  `json:"totalCents" firestore:"totalCents"`
	Allocations   []groupOrderAllocation `json:"allocations" firestore:"allocations"`
}

type groupOrderSession struct {
	ID              string                  `json:"id" firestore:"id"`
	JoinCode        string                  `json:"joinCode" firestore:"joinCode"`
	OrderID         string                  `json:"orderId,omitempty" firestore:"orderId,omitempty"`
	TenantID        string                  `json:"tenantId" firestore:"tenantId"`
	StoreID         string                  `json:"storeId" firestore:"storeId"`
	CustomerID      string                  `json:"customerId,omitempty" firestore:"customerId,omitempty"`
	FulfillmentType string                  `json:"fulfillmentType" firestore:"fulfillmentType"`
	Delivery        *orderDelivery          `json:"delivery,omitempty" firestore:"delivery,omitempty"`
	Status          string                  `json:"status" firestore:"status"`
	Host            channelContact          `json:"host" firestore:"host"`
	Participants    []groupOrderParticipant `json:"participants" firestore:"participants"`
	Items           []orderItem             `json:"items" firestore:"items"`
	Pricing         groupOrderPricing       `json:"pricing" firestore:"pricing"`
	PaymentMode     string                  `json:"paymentMode" firestore:"paymentMode"`
	PaymentMethod   string                  `json:"paymentMethod" firestore:"paymentMethod"`
	ExpiresAt       time.Time               `json:"expiresAt" firestore:"expiresAt"`
	CreatedAt       time.Time               `json:"createdAt" firestore:"createdAt"`
	UpdatedAt       time.Time               `json:"updatedAt" firestore:"updatedAt"`
}

type groupOrderInvite struct {
	InviteID     string    `json:"inviteId" firestore:"inviteId"`
	GroupOrderID string    `json:"groupOrderId" firestore:"groupOrderId"`
	CreatedByID  string    `json:"createdById" firestore:"createdById"`
	CreatedAt    time.Time `json:"createdAt" firestore:"createdAt"`
	ExpiresAt    time.Time `json:"expiresAt" firestore:"expiresAt"`
	UsesCount    int       `json:"usesCount" firestore:"usesCount"`
	MaxUses      int       `json:"maxUses,omitempty" firestore:"maxUses,omitempty"`
	UsedAt       time.Time `json:"usedAt,omitempty" firestore:"usedAt,omitempty"`
	UsedByID     string    `json:"usedById,omitempty" firestore:"usedById,omitempty"`
}
