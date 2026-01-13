package main

import "strings"

var allowedMobileProviders = map[string]struct{}{
	"facebook": {},
	"discord":  {},
	"snapchat": {},
	"tiktok":   {},
	"telegram": {},
}

func normalizeMobileProvider(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	return value
}

func isAllowedMobileProvider(provider string) bool {
	_, ok := allowedMobileProviders[provider]
	return ok
}

func normalizeMobilePlatform(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		return "mobile"
	}
	return value
}
