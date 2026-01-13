package main

type webAppGroupOrderCreateRequest struct {
	SessionID       string `json:"sessionId"`
	StoreID         string `json:"storeId,omitempty"`
	PaymentMode     string `json:"paymentMode"`
	PaymentMethod   string `json:"paymentMethod,omitempty"`
	FulfillmentType string `json:"fulfillmentType,omitempty"`
	DisplayName     string `json:"displayName,omitempty"`
}

type groupOrderCreatePayload struct {
	TenantID        string         `json:"tenantId"`
	StoreID         string         `json:"storeId"`
	CustomerID      string         `json:"customerId,omitempty"`
	FulfillmentType string         `json:"fulfillmentType,omitempty"`
	PaymentMode     string         `json:"paymentMode"`
	PaymentMethod   string         `json:"paymentMethod,omitempty"`
	Host            channelContact `json:"host"`
	ParticipantID   string         `json:"participantId,omitempty"`
	DisplayName     string         `json:"displayName,omitempty"`
}

type webAppGroupOrderJoinRequest struct {
	SessionID   string `json:"sessionId"`
	DisplayName string `json:"displayName,omitempty"`
	InviteID    string `json:"inviteId,omitempty"`
}

type groupOrderJoinPayload struct {
	ParticipantID string         `json:"participantId,omitempty"`
	Contact       channelContact `json:"channelContact"`
	DisplayName   string         `json:"displayName,omitempty"`
	InviteID      string         `json:"inviteId,omitempty"`
}

type webAppGroupOrderInviteRequest struct {
	SessionID string `json:"sessionId"`
}

type groupOrderInviteCreatePayload struct {
	ParticipantID string         `json:"participantId,omitempty"`
	Contact       channelContact `json:"channelContact"`
}

type webAppGroupOrderItem struct {
	ItemID             string                    `json:"itemId"`
	Name               string                    `json:"name"`
	Quantity           int                       `json:"quantity"`
	PriceCents         int64                     `json:"priceCents"`
	Category           string                    `json:"category,omitempty"`
	ModifierSelections []webAppModifierSelection `json:"modifierSelections,omitempty"`
}

type webAppGroupOrderItemsRequest struct {
	SessionID        string                 `json:"sessionId"`
	ParticipantID    string                 `json:"participantId"`
	ParticipantLabel string                 `json:"participantLabel,omitempty"`
	Items            []webAppGroupOrderItem `json:"items"`
}

type groupOrderItemsPayload struct {
	ParticipantID    string                 `json:"participantId"`
	ParticipantLabel string                 `json:"participantLabel,omitempty"`
	Items            []webAppGroupOrderItem `json:"items"`
}

type webAppGroupOrderLockRequest struct {
	SessionID     string `json:"sessionId,omitempty"`
	TaxCents      int64  `json:"taxCents"`
	FeeCents      int64  `json:"feeCents"`
	DiscountCents int64  `json:"discountCents"`
}

type webAppGroupOrderCheckoutRequest struct {
	SessionID     string `json:"sessionId,omitempty"`
	ParticipantID string `json:"participantId,omitempty"`
	SuccessURL    string `json:"successUrl"`
	CancelURL     string `json:"cancelUrl"`
	Currency      string `json:"currency,omitempty"`
}

type webAppGroupOrderSubmitRequest struct {
	SessionID string `json:"sessionId,omitempty"`
}
