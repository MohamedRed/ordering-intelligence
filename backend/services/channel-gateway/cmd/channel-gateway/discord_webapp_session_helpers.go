package main

import (
	"context"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func buildDiscordSession(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	storeID string,
	storeMeta storeMetadata,
	user discordUserResponse,
	displayName string,
) (channelSession, error) {
	accountID := strings.TrimSpace(cfg.DiscordClientID)
	if accountID == "" {
		accountID = "discord_webapp"
	}
	session := channelSession{
		Channel:                  "discord_webapp",
		AccountID:                accountID,
		UserID:                   user.ID,
		DisplayName:              displayName,
		TenantID:                 storeMeta.TenantID,
		StoreID:                  storeID,
		BusinessType:             storeMeta.BusinessType,
		AuthProvider:             webAppAuthProvider("discord_webapp"),
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
