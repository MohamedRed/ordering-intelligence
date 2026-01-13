package main

type mobileSessionStartRequest struct {
	Provider        string `json:"provider"`
	ProviderUserID  string `json:"providerUserId"`
	DisplayName     string `json:"displayName"`
	StoreID         string `json:"storeId"`
	Locale          string `json:"locale"`
	AccessToken     string `json:"accessToken"`
	AuthCode        string `json:"authCode"`
	CodeVerifier    string `json:"codeVerifier"`
	RedirectURI     string `json:"redirectUri"`
	ClientVersion   string `json:"clientVersion"`
	Signature       string `json:"signature"`
	Timestamp       string `json:"timestamp"`
	DeviceID        string `json:"deviceId"`
	ClientPlatform  string `json:"clientPlatform"`
	ClientApp       string `json:"clientApp"`
	ClientOS        string `json:"clientOs"`
	ClientOSVersion string `json:"clientOsVersion"`
}

type mobileSessionStartResponse struct {
	SessionID              string `json:"sessionId"`
	AccountID              string `json:"accountId"`
	UserID                 string `json:"userId"`
	DisplayName            string `json:"displayName"`
	StoreID                string `json:"storeId,omitempty"`
	StoreName              string `json:"storeName,omitempty"`
	TenantID               string `json:"tenantId,omitempty"`
	CustomerID             string `json:"customerId,omitempty"`
	BusinessType           string `json:"businessType,omitempty"`
	Currency               string `json:"currency,omitempty"`
	FuelDefaultPrepayCents int64  `json:"fuelDefaultPrepayCents,omitempty"`
	FuelPreauthCapCents    int64  `json:"fuelPreauthCapCents,omitempty"`
}
