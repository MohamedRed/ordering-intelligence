package main

import "strings"

type customerSeenContext struct {
	Channel  string
	StoreID  string
	Platform string
	Provider string
}

func buildSeenContext(channel, storeID, platform, provider string) customerSeenContext {
	ctx := customerSeenContext{
		Channel:  normalizeChannel(channel),
		StoreID:  strings.TrimSpace(storeID),
		Platform: strings.ToLower(strings.TrimSpace(platform)),
		Provider: strings.ToLower(strings.TrimSpace(provider)),
	}
	if ctx.Provider == "" {
		ctx.Provider = ctx.Channel
	}
	return ctx
}
