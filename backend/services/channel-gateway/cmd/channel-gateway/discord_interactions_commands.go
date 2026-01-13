package main

import (
	"context"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

const discordCommandLiive = "liive"

func buildDiscordCommandResponse(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	interaction discordInteraction,
) discordInteractionResponse {
	data := interaction.Data
	if data == nil {
		return discordTextResponse("Unsupported command.")
	}
	command := strings.ToLower(strings.TrimSpace(data.Name))
	if command != discordCommandLiive {
		return discordTextResponse("Unsupported command.")
	}
	query := discordOptionValue(data.Options, map[string]bool{
		"query":      true,
		"restaurant": true,
		"store":      true,
		"name":       true,
	})
	if strings.TrimSpace(query) == "" {
		return discordTextResponse("Usage: /liive <restaurant name>")
	}
	choices, err := searchStoreChoices(ctx, cfg, firestoreClient, query)
	if err != nil || len(choices) == 0 {
		return discordTextResponse("No matching restaurants found.")
	}
	content, components := buildDiscordStoreComponents(choices)
	return discordResponse(content, components)
}

func discordOptionValue(options []discordInteractionOption, accepted map[string]bool) string {
	for _, option := range options {
		name := strings.ToLower(strings.TrimSpace(option.Name))
		if option.Value != nil && accepted[name] {
			if value, ok := option.Value.(string); ok {
				return strings.TrimSpace(value)
			}
		}
		if len(option.Options) > 0 {
			if nested := discordOptionValue(option.Options, accepted); nested != "" {
				return nested
			}
		}
	}
	return ""
}
