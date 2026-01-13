package main

import "strings"

func canReplaceChannelContact(existing, incoming *channelContact) bool {
	if existing == nil || incoming == nil {
		return false
	}
	existingChannel := strings.TrimSpace(strings.ToLower(existing.Channel))
	incomingChannel := strings.TrimSpace(strings.ToLower(incoming.Channel))
	if incomingChannel != "telegram" {
		return false
	}
	if existingChannel != "telegram_webapp" && existingChannel != "webapp" {
		return false
	}
	existingUser := strings.TrimSpace(existing.UserID)
	incomingUser := strings.TrimSpace(incoming.UserID)
	if existingUser != "" && incomingUser != "" && existingUser == incomingUser {
		return true
	}
	existingAccount := strings.TrimSpace(existing.AccountID)
	incomingAccount := strings.TrimSpace(incoming.AccountID)
	if existingAccount != "" && incomingAccount != "" && existingAccount == incomingAccount {
		return true
	}
	return false
}
