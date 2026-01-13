package main

import (
	"context"
	"log"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleDiscordComponentInteraction(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	interaction discordInteraction,
) discordInteractionResponse {
	if interaction.Data == nil {
		return discordTextResponse("Unsupported action.")
	}
	storeID, startGroup, ok := parseDiscordStoreActionID(strings.TrimSpace(interaction.Data.CustomID))
	if !ok {
		return discordTextResponse("Unsupported action.")
	}
	userID := discordInteractionUserID(interaction)
	if userID == "" {
		return discordTextResponse("Unable to resolve your Discord user.")
	}
	if err := recordDiscordPendingSelection(ctx, cfg, firestoreClient, userID, storeID, startGroup); err != nil {
		return discordTextResponse("Unable to prepare your order right now.")
	}
	fallbackURL := buildDiscordWebAppURL(
		resolveDiscordWebAppURL(ctx, cfg, firestoreClient),
		storeID,
		startGroup,
	)
	inviteURL, err := createDiscordActivityInvite(ctx, cfg)
	if err != nil {
		log.Printf("discord activity invite failed store=%s group=%t err=%v", storeID, startGroup, err)
	}
	if err != nil && strings.TrimSpace(fallbackURL) == "" {
		return discordTextResponse("Unable to open Liive right now.")
	}
	content := "Open Liive:"
	if startGroup {
		content = "Open your group order:"
	}
	return discordResponse(
		content,
		buildDiscordInviteComponents(inviteURL, fallbackURL),
	)
}
