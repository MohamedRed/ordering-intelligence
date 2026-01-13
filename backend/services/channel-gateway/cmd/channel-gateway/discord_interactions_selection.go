package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

const discordSelectionTTL = 15 * time.Minute

type discordPendingSelection struct {
	StoreID         string    `firestore:"store_id" json:"storeId"`
	StartGroupOrder bool      `firestore:"start_group_order" json:"startGroupOrder"`
	SelectedAt      time.Time `firestore:"selected_at" json:"selectedAt"`
}

func buildDiscordStoreActionID(storeID string, startGroup bool) string {
	flag := "0"
	if startGroup {
		flag = "1"
	}
	return fmt.Sprintf("liive:store:%s:group:%s", strings.TrimSpace(storeID), flag)
}

func parseDiscordStoreActionID(customID string) (string, bool, bool) {
	if !strings.HasPrefix(customID, "liive:store:") {
		return "", false, false
	}
	payload := strings.TrimPrefix(customID, "liive:store:")
	parts := strings.Split(payload, ":group:")
	if len(parts) != 2 {
		return "", false, false
	}
	storeID := strings.TrimSpace(parts[0])
	if storeID == "" {
		return "", false, false
	}
	groupFlag := strings.TrimSpace(parts[1])
	startGroup := groupFlag == "1" || strings.EqualFold(groupFlag, "true")
	return storeID, startGroup, true
}

func recordDiscordPendingSelection(
	ctx context.Context,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
	userID string,
	storeID string,
	startGroup bool,
) error {
	userID = strings.TrimSpace(userID)
	storeID = strings.TrimSpace(storeID)
	if userID == "" || storeID == "" {
		return nil
	}
	accountID := strings.TrimSpace(cfg.DiscordClientID)
	if accountID == "" {
		accountID = "discord"
	}
	existing, err := fetchSession(ctx, client, "discord", accountID, userID)
	if err != nil {
		return err
	}
	selection := &discordPendingSelection{
		StoreID:         storeID,
		StartGroupOrder: startGroup,
		SelectedAt:      time.Now().UTC(),
	}
	session := channelSession{
		Channel:                 "discord",
		AccountID:               accountID,
		UserID:                  userID,
		DisplayName:             "",
		PendingDiscordSelection: selection,
		LastSeenAt:              time.Now().UTC(),
		CreatedAt:               sessionCreatedAt(existing),
	}
	if existing != nil {
		session.DisplayName = existing.DisplayName
	}
	return upsertSession(ctx, client, session)
}

func consumeDiscordPendingSelection(
	ctx context.Context,
	cfg *serviceConfig,
	client *cloudfirestore.Client,
	userID string,
) (*discordPendingSelection, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return nil, nil
	}
	accountID := strings.TrimSpace(cfg.DiscordClientID)
	if accountID == "" {
		accountID = "discord"
	}
	session, err := fetchSession(ctx, client, "discord", accountID, userID)
	if err != nil {
		return nil, err
	}
	if session == nil || session.PendingDiscordSelection == nil {
		return nil, nil
	}
	selection := session.PendingDiscordSelection
	if !selection.SelectedAt.IsZero() && time.Since(selection.SelectedAt) > discordSelectionTTL {
		session.PendingDiscordSelection = nil
		_ = upsertSession(ctx, client, *session)
		return nil, nil
	}
	session.PendingDiscordSelection = nil
	session.LastSeenAt = time.Now().UTC()
	_ = upsertSession(ctx, client, *session)
	return selection, nil
}
