package main

import "time"

type customerProfileResolveRequest struct {
	TenantID    string `json:"tenantId,omitempty"`
	Channel     string `json:"channel"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	StoreID     string `json:"storeId,omitempty"`
	Platform    string `json:"platform,omitempty"`
	Provider    string `json:"provider,omitempty"`
	AllowCreate bool   `json:"allowCreate"`
}

type customerProfileIdentity struct {
	Channel     string    `json:"channel"`
	UserID      string    `json:"userId"`
	DisplayName string    `json:"displayName,omitempty"`
	LinkedAt    time.Time `json:"linkedAt"`
	LastSeenAt  time.Time `json:"lastSeenAt"`
}

type customerProfileResponse struct {
	CustomerID        string                    `json:"customerId"`
	TenantID          string                    `json:"tenantId,omitempty"`
	DisplayName       string                    `json:"displayName"`
	Status            string                    `json:"status"`
	LinkedConsentAt   time.Time                 `json:"linkedConsentAt,omitempty"`
	CreatedAt         time.Time                 `json:"createdAt,omitempty"`
	UpdatedAt         time.Time                 `json:"updatedAt,omitempty"`
	FirstSeenAt       time.Time                 `json:"firstSeenAt,omitempty"`
	FirstSeenChannel  string                    `json:"firstSeenChannel,omitempty"`
	FirstSeenStoreID  string                    `json:"firstSeenStoreId,omitempty"`
	FirstSeenPlatform string                    `json:"firstSeenPlatform,omitempty"`
	FirstSeenProvider string                    `json:"firstSeenProvider,omitempty"`
	LastSeenAt        time.Time                 `json:"lastSeenAt,omitempty"`
	LastSeenChannel   string                    `json:"lastSeenChannel,omitempty"`
	LastSeenStoreID   string                    `json:"lastSeenStoreId,omitempty"`
	LastSeenPlatform  string                    `json:"lastSeenPlatform,omitempty"`
	LastSeenProvider  string                    `json:"lastSeenProvider,omitempty"`
	FuelPreauthCapCents int64                   `json:"fuelPreauthCapCents,omitempty"`
	LinkedChannels    []customerProfileIdentity `json:"linkedChannels"`
}
