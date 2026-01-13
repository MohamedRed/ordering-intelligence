package main

import "time"

const (
	customersCollection      = "customers"
	identitiesCollection     = "customer_identities"
	linkTokensCollection     = "customer_link_tokens"
	customerEventsCollection = "customer_events"
)

type pubsubPushEnvelope struct {
	Message struct {
		Data string `json:"data"`
		ID   string `json:"messageId"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type orderEvent struct {
	ID           string    `json:"id"`
	StoreID      string    `json:"storeId"`
	CustomerName string    `json:"customerName"`
	CreatedAt    time.Time `json:"createdAt"`
	CustomerID   string    `json:"customerId"`
	TenantID     string    `json:"tenantId,omitempty"`
	CallerID     string    `json:"callerId,omitempty"`
}

type customerRecord struct {
	CustomerID        string    `firestore:"customerId" json:"customerId"`
	DisplayName       string    `firestore:"displayName" json:"displayName"`
	Status            string    `firestore:"status" json:"status"`
	MergedInto        string    `firestore:"mergedInto,omitempty" json:"mergedInto,omitempty"`
	LinkedConsentAt   time.Time `firestore:"linkedConsentAt,omitempty" json:"linkedConsentAt,omitempty"`
	CreatedAt         time.Time `firestore:"createdAt" json:"createdAt"`
	UpdatedAt         time.Time `firestore:"updatedAt" json:"updatedAt"`
	FirstSeenAt       time.Time `firestore:"firstSeenAt,omitempty" json:"firstSeenAt,omitempty"`
	FirstSeenChannel  string    `firestore:"firstSeenChannel,omitempty" json:"firstSeenChannel,omitempty"`
	FirstSeenStoreID  string    `firestore:"firstSeenStoreId,omitempty" json:"firstSeenStoreId,omitempty"`
	FirstSeenPlatform string    `firestore:"firstSeenPlatform,omitempty" json:"firstSeenPlatform,omitempty"`
	FirstSeenProvider string    `firestore:"firstSeenProvider,omitempty" json:"firstSeenProvider,omitempty"`
	LastSeenAt        time.Time `firestore:"lastSeenAt" json:"lastSeenAt"`
	LastSeenChannel   string    `firestore:"lastSeenChannel,omitempty" json:"lastSeenChannel,omitempty"`
	LastSeenStoreID   string    `firestore:"lastSeenStoreId,omitempty" json:"lastSeenStoreId,omitempty"`
	LastSeenPlatform  string    `firestore:"lastSeenPlatform,omitempty" json:"lastSeenPlatform,omitempty"`
	LastSeenProvider  string    `firestore:"lastSeenProvider,omitempty" json:"lastSeenProvider,omitempty"`
	LastOrderAt       time.Time `firestore:"lastOrderAt,omitempty" json:"lastOrderAt,omitempty"`
	FuelPreauthCapCents int64   `firestore:"fuelPreauthCapCents,omitempty" json:"fuelPreauthCapCents,omitempty"`
}

type customerIdentity struct {
	CustomerID  string    `firestore:"customerId" json:"customerId"`
	Channel     string    `firestore:"channel" json:"channel"`
	UserID      string    `firestore:"userId" json:"userId"`
	DisplayName string    `firestore:"displayName,omitempty" json:"displayName,omitempty"`
	LinkedAt    time.Time `firestore:"linkedAt" json:"linkedAt"`
	LastSeenAt  time.Time `firestore:"lastSeenAt" json:"lastSeenAt"`
	VerifiedAt  time.Time `firestore:"verifiedAt,omitempty" json:"verifiedAt,omitempty"`
}

type linkTokenRecord struct {
	Token         string    `firestore:"token" json:"token"`
	CustomerID    string    `firestore:"customerId" json:"customerId"`
	TargetChannel string    `firestore:"targetChannel" json:"targetChannel"`
	CreatedAt     time.Time `firestore:"createdAt" json:"createdAt"`
	ExpiresAt     time.Time `firestore:"expiresAt" json:"expiresAt"`
	UsedAt        time.Time `firestore:"usedAt,omitempty" json:"usedAt,omitempty"`
	UsedByChannel string    `firestore:"usedByChannel,omitempty" json:"usedByChannel,omitempty"`
	UsedByUserID  string    `firestore:"usedByUserId,omitempty" json:"usedByUserId,omitempty"`
}

type customerEvent struct {
	CustomerID string            `firestore:"customerId" json:"customerId"`
	EventType  string            `firestore:"eventType" json:"eventType"`
	Channel    string            `firestore:"channel,omitempty" json:"channel,omitempty"`
	UserID     string            `firestore:"userId,omitempty" json:"userId,omitempty"`
	TenantID   string            `firestore:"tenantId,omitempty" json:"tenantId,omitempty"`
	CreatedAt  time.Time         `firestore:"createdAt" json:"createdAt"`
	Metadata   map[string]string `firestore:"metadata,omitempty" json:"metadata,omitempty"`
}
