package main

import "time"

type customerIdentityView struct {
	Channel     string    `json:"channel"`
	UserID      string    `json:"userId"`
	DisplayName string    `json:"displayName,omitempty"`
	LinkedAt    time.Time `json:"linkedAt"`
	LastSeenAt  time.Time `json:"lastSeenAt"`
}

type customerResponse struct {
	CustomerID        string                 `json:"customerId"`
	DisplayName       string                 `json:"displayName"`
	Status            string                 `json:"status"`
	LinkedConsentAt   time.Time              `json:"linkedConsentAt,omitempty"`
	CreatedAt         time.Time              `json:"createdAt"`
	UpdatedAt         time.Time              `json:"updatedAt"`
	FirstSeenAt       time.Time              `json:"firstSeenAt,omitempty"`
	FirstSeenChannel  string                 `json:"firstSeenChannel,omitempty"`
	FirstSeenStoreID  string                 `json:"firstSeenStoreId,omitempty"`
	FirstSeenPlatform string                 `json:"firstSeenPlatform,omitempty"`
	FirstSeenProvider string                 `json:"firstSeenProvider,omitempty"`
	LastSeenAt        time.Time              `json:"lastSeenAt"`
	LastSeenChannel   string                 `json:"lastSeenChannel,omitempty"`
	LastSeenStoreID   string                 `json:"lastSeenStoreId,omitempty"`
	LastSeenPlatform  string                 `json:"lastSeenPlatform,omitempty"`
	LastSeenProvider  string                 `json:"lastSeenProvider,omitempty"`
	FuelPreauthCapCents int64                `json:"fuelPreauthCapCents,omitempty"`
	LinkedChannels    []customerIdentityView `json:"linkedChannels"`
}

func buildCustomerResponse(record customerRecord, identities []customerIdentity) customerResponse {
	linked := make([]customerIdentityView, 0, len(identities))
	for _, identity := range identities {
		linked = append(linked, customerIdentityView{
			Channel:     normalizeChannel(identity.Channel),
			UserID:      identity.UserID,
			DisplayName: identity.DisplayName,
			LinkedAt:    identity.LinkedAt,
			LastSeenAt:  identity.LastSeenAt,
		})
	}
	return customerResponse{
		CustomerID:        record.CustomerID,
		DisplayName:       record.DisplayName,
		Status:            record.Status,
		LinkedConsentAt:   record.LinkedConsentAt,
		CreatedAt:         record.CreatedAt,
		UpdatedAt:         record.UpdatedAt,
		FirstSeenAt:       record.FirstSeenAt,
		FirstSeenChannel:  record.FirstSeenChannel,
		FirstSeenStoreID:  record.FirstSeenStoreID,
		FirstSeenPlatform: record.FirstSeenPlatform,
		FirstSeenProvider: record.FirstSeenProvider,
		LastSeenAt:        record.LastSeenAt,
		LastSeenChannel:   record.LastSeenChannel,
		LastSeenStoreID:   record.LastSeenStoreID,
		LastSeenPlatform:  record.LastSeenPlatform,
		LastSeenProvider:  record.LastSeenProvider,
		FuelPreauthCapCents: record.FuelPreauthCapCents,
		LinkedChannels:    linked,
	}
}
