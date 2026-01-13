package main

import "strings"

func discordInteractionUserID(interaction discordInteraction) string {
	if interaction.Member != nil && interaction.Member.User != nil {
		id := strings.TrimSpace(interaction.Member.User.ID)
		if id != "" {
			return id
		}
	}
	if interaction.User != nil {
		return strings.TrimSpace(interaction.User.ID)
	}
	return ""
}
