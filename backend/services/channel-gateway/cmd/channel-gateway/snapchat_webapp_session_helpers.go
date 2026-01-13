package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func buildSnapchatSession(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	storeID string,
	storeMeta storeMetadata,
	user snapchatUserResponse,
) (channelSession, error) {
	accountID := strings.TrimSpace(cfg.SnapchatClientID)
	if accountID == "" {
		accountID = "snapchat_webapp"
	}
	displayName := strings.TrimSpace(user.DisplayName)
	if displayName == "" {
		displayName = "Snapchat Customer"
	}
	session := channelSession{
		Channel:                  "snapchat_webapp",
		AccountID:                accountID,
		UserID:                   strings.TrimSpace(user.ExternalID),
		DisplayName:              displayName,
		TenantID:                 storeMeta.TenantID,
		StoreID:                  storeID,
		BusinessType:             storeMeta.BusinessType,
		AuthProvider:             webAppAuthProvider("snapchat_webapp"),
		ClientPlatform:           "web",
		ClientApp:                "consumer-web",
		ElevenLabsConversationID: "",
		LastSeenAt:               time.Now().UTC(),
		CreatedAt:                time.Now().UTC(),
	}
	if customerID, err := resolveCustomerID(ctx, cfg, session.Channel, session.UserID, session.DisplayName, session.TenantID, customerResolveContext{
		StoreID:  storeID,
		Platform: "web",
	}); err == nil {
		session.CustomerID = customerID
	}
	if err := upsertSession(ctx, firestoreClient, session); err != nil {
		return channelSession{}, err
	}
	return session, nil
}
