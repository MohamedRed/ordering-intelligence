package main

import (
	"fmt"
	"strings"
)

func webAppOrderChannel(session channelSession) string {
	channel := strings.TrimSpace(session.Channel)
	if channel != "" {
		return channel
	}
	return "telegram_webapp"
}

func webAppContactChannel(channel string) string {
	switch strings.ToLower(strings.TrimSpace(channel)) {
	case "discord_webapp", "discord":
		return "discord"
	case "snapchat_webapp", "snapchat":
		return "snapchat"
	case "telegram_webapp", "telegram":
		return "telegram_webapp"
	default:
		return strings.TrimSpace(channel)
	}
}

func webAppCallerPrefix(channel string) string {
	switch strings.ToLower(strings.TrimSpace(channel)) {
	case "telegram_webapp", "telegram":
		return "telegram"
	case "discord_webapp", "discord":
		return "discord"
	case "snapchat_webapp", "snapchat":
		return "snapchat"
	case "mobile":
		return "mobile"
	default:
		return strings.TrimSpace(channel)
	}
}

func normalizeProviderFromChannel(channel string) string {
	switch strings.ToLower(strings.TrimSpace(channel)) {
	case "telegram_webapp", "telegram":
		return "telegram"
	case "discord_webapp", "discord":
		return "discord"
	case "snapchat_webapp", "snapchat":
		return "snapchat"
	case "mobile":
		return "mobile"
	default:
		return strings.TrimSpace(channel)
	}
}

func webAppAuthProvider(channel string) string {
	return normalizeProviderFromChannel(channel)
}

func webAppCallerID(channel, userID string) string {
	user := strings.TrimSpace(userID)
	prefix := webAppCallerPrefix(channel)
	if user == "" || prefix == "" {
		return ""
	}
	return fmt.Sprintf("%s:%s", prefix, user)
}

func webAppDefaultCustomerName(channel string) string {
	switch strings.ToLower(strings.TrimSpace(channel)) {
	case "discord_webapp", "discord":
		return "Discord Customer"
	case "snapchat_webapp", "snapchat":
		return "Snapchat Customer"
	case "mobile":
		return "Mobile Customer"
	default:
		return "Telegram Customer"
	}
}
