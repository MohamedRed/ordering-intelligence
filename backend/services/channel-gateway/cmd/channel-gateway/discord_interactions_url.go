package main

import (
	"context"
	"net/url"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/ordering-intelligence/agentcontext"
)

func resolveDiscordWebAppURL(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) string {
	base := strings.TrimSpace(cfg.TelegramWebAppURL)
	if firestoreClient == nil || cfg.DiscordClientID == "" {
		return base
	}
	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          "discord",
		ChannelAccountID: cfg.DiscordClientID,
	})
	if err != nil || route == nil {
		return base
	}
	return strings.TrimSpace(firstNonEmpty(
		anyToString(route.Data["webapp_url"]),
		anyToString(route.Data["webappUrl"]),
		anyToString(route.Data["web_app_url"]),
		base,
	))
}

func buildDiscordWebAppURL(baseURL, storeID string, startGroup bool) string {
	if strings.TrimSpace(baseURL) == "" {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil {
		return baseURL
	}
	params := parsed.Query()
	params.Set("platform", "discord")
	if strings.TrimSpace(storeID) != "" {
		params.Set("storeId", storeID)
	}
	if startGroup {
		params.Set("startGroupOrder", "1")
	}
	params.Set("source", "discord_command")
	parsed.RawQuery = params.Encode()
	return parsed.String()
}
