package main

import "time"

const (
	tvPairingStatusPending = "pending"
	tvPairingStatusLinked  = "linked"
	tvPairingStatusExpired = "expired"
)

type tvPairingStartRequest struct {
	DeviceID       string `json:"deviceId"`
	DeviceType     string `json:"deviceType"`
	DeviceName     string `json:"deviceName"`
	Locale         string `json:"locale"`
	ClientVersion  string `json:"clientVersion"`
	ClientPlatform string `json:"clientPlatform"`
}

type tvPairingStartResponse struct {
	PairingID           string `json:"pairingId"`
	Code                string `json:"code"`
	PairURL             string `json:"pairUrl"`
	ExpiresAt           string `json:"expiresAt"`
	PollIntervalSeconds int    `json:"pollIntervalSeconds"`
}

type tvPairingStateResponse struct {
	Status       string `json:"status"`
	PairingID    string `json:"pairingId,omitempty"`
	Code         string `json:"code,omitempty"`
	ExpiresAt    string `json:"expiresAt,omitempty"`
	SessionID    string `json:"sessionId,omitempty"`
	SessionToken string `json:"sessionToken,omitempty"`
	CustomerID   string `json:"customerId,omitempty"`
	DisplayName  string `json:"displayName,omitempty"`
	LinkedAt     string `json:"linkedAt,omitempty"`
	Linked       bool   `json:"linked,omitempty"`
	Session      string `json:"session,omitempty"`
}

type tvPairingCompleteRequest struct {
	PairingID  string `json:"pairingId"`
	Code       string `json:"code"`
	SessionID  string `json:"sessionId"`
	DeviceName string `json:"deviceName"`
}

type tvPairingRecord struct {
	PairingID      string    `firestore:"pairing_id" json:"pairingId"`
	Code           string    `firestore:"code" json:"code"`
	Status         string    `firestore:"status" json:"status"`
	DeviceID       string    `firestore:"device_id,omitempty" json:"deviceId,omitempty"`
	DeviceType     string    `firestore:"device_type,omitempty" json:"deviceType,omitempty"`
	DeviceName     string    `firestore:"device_name,omitempty" json:"deviceName,omitempty"`
	ClientVersion  string    `firestore:"client_version,omitempty" json:"clientVersion,omitempty"`
	ClientPlatform string    `firestore:"client_platform,omitempty" json:"clientPlatform,omitempty"`
	Locale         string    `firestore:"locale,omitempty" json:"locale,omitempty"`
	SessionID      string    `firestore:"session_id,omitempty" json:"sessionId,omitempty"`
	SessionToken   string    `firestore:"session_token,omitempty" json:"sessionToken,omitempty"`
	CustomerID     string    `firestore:"customer_id,omitempty" json:"customerId,omitempty"`
	DisplayName    string    `firestore:"display_name,omitempty" json:"displayName,omitempty"`
	CreatedAt      time.Time `firestore:"created_at" json:"createdAt"`
	ExpiresAt      time.Time `firestore:"expires_at" json:"expiresAt"`
	LinkedAt       time.Time `firestore:"linked_at,omitempty" json:"linkedAt,omitempty"`
}

type tvSessionRecord struct {
	SessionToken string    `firestore:"session_token" json:"sessionToken"`
	SessionID    string    `firestore:"session_id" json:"sessionId"`
	CustomerID   string    `firestore:"customer_id,omitempty" json:"customerId,omitempty"`
	DeviceID     string    `firestore:"device_id,omitempty" json:"deviceId,omitempty"`
	DeviceType   string    `firestore:"device_type,omitempty" json:"deviceType,omitempty"`
	CreatedAt    time.Time `firestore:"created_at" json:"createdAt"`
	ExpiresAt    time.Time `firestore:"expires_at" json:"expiresAt"`
	LastSeenAt   time.Time `firestore:"last_seen_at" json:"lastSeenAt"`
}

type tvSessionResponse struct {
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
