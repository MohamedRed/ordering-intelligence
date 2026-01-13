package main

import (
	"fmt"
	"strings"
)

const maxDiscordStoreChoices = 3

func discordResponse(content string, components []discordComponent) discordInteractionResponse {
	return discordInteractionResponse{
		Type: discordResponseMessage,
		Data: &discordInteractionResponseData{
			Content:    strings.TrimSpace(content),
			Flags:      discordEphemeralFlag,
			Components: components,
		},
	}
}

func discordTextResponse(content string) discordInteractionResponse {
	return discordResponse(content, nil)
}

func buildDiscordStoreComponents(choices []storeChoice) (string, []discordComponent) {
	limit := len(choices)
	if limit > maxDiscordStoreChoices {
		limit = maxDiscordStoreChoices
	}
	var b strings.Builder
	b.WriteString("Choose a restaurant:\n")
	components := make([]discordComponent, 0, limit)
	for i := 0; i < limit; i++ {
		choice := choices[i]
		b.WriteString(fmt.Sprintf("%d) %s\n", i+1, choice.Name))
		components = append(components, discordComponent{
			Type: discordComponentActionRow,
			Components: []discordComponent{
				{
					Type:     discordComponentButton,
					Style:    discordButtonStylePrimary,
					Label:    "Order for me",
					CustomID: buildDiscordStoreActionID(choice.StoreID, false),
				},
				{
					Type:     discordComponentButton,
					Style:    discordButtonStylePrimary,
					Label:    "Start group order",
					CustomID: buildDiscordStoreActionID(choice.StoreID, true),
				},
			},
		})
	}
	return strings.TrimSpace(b.String()), components
}

func buildDiscordInviteComponents(inviteURL, fallbackURL string) []discordComponent {
	inviteURL = strings.TrimSpace(inviteURL)
	fallbackURL = strings.TrimSpace(fallbackURL)
	if inviteURL == "" && fallbackURL == "" {
		return nil
	}
	row := discordComponent{
		Type:       discordComponentActionRow,
		Components: []discordComponent{},
	}
	if inviteURL != "" {
		row.Components = append(row.Components, discordComponent{
			Type:  discordComponentButton,
			Style: discordButtonStyleLink,
			Label: "Open in Discord",
			URL:   inviteURL,
		})
	}
	if fallbackURL != "" {
		row.Components = append(row.Components, discordComponent{
			Type:  discordComponentButton,
			Style: discordButtonStyleLink,
			Label: "Open in browser",
			URL:   fallbackURL,
		})
	}
	return []discordComponent{row}
}
