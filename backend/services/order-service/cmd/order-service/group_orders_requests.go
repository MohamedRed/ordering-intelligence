package main

type groupOrderCreateRequest struct {
	TenantID        string         `json:"tenantId"`
	StoreID         string         `json:"storeId"`
	CustomerID      string         `json:"customerId,omitempty"`
	FulfillmentType string         `json:"fulfillmentType"`
	Delivery        *orderDelivery `json:"delivery,omitempty"`
	PaymentMode     string         `json:"paymentMode"`
	PaymentMethod   string         `json:"paymentMethod,omitempty"`
	Host            channelContact `json:"host"`
	ParticipantID   string         `json:"participantId,omitempty"`
	DisplayName     string         `json:"displayName,omitempty"`
}

type groupOrderJoinRequest struct {
	ParticipantID string         `json:"participantId,omitempty"`
	Contact       channelContact `json:"channelContact"`
	DisplayName   string         `json:"displayName,omitempty"`
	InviteID      string         `json:"inviteId,omitempty"`
}

type groupOrderAddItemsRequest struct {
	ParticipantID    string      `json:"participantId"`
	ParticipantLabel string      `json:"participantLabel,omitempty"`
	Items            []orderItem `json:"items"`
}

type groupOrderLockRequest struct {
	TaxCents      int64 `json:"taxCents"`
	FeeCents      int64 `json:"feeCents"`
	DiscountCents int64 `json:"discountCents"`
}

type groupOrderSubmitRequest struct {
	IdempotencyKey string `json:"idempotencyKey,omitempty"`
}

type groupOrderInviteCreateRequest struct {
	ParticipantID string         `json:"participantId,omitempty"`
	Contact       channelContact `json:"channelContact"`
	ExpiresInMins int            `json:"expiresInMinutes,omitempty"`
	MaxUses       int            `json:"maxUses,omitempty"`
}

type groupOrderResponse struct {
	GroupOrder groupOrderSession `json:"groupOrder"`
}

type groupOrderInviteResponse struct {
	Invite groupOrderInvite `json:"invite"`
}
