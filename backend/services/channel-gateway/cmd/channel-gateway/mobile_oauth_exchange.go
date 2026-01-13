package main

import (
	"context"
	"errors"
	"strings"
)

var errMobileOAuthNotConfigured = errors.New("mobile_oauth_not_configured")

func exchangeMobileOAuthToken(
	ctx context.Context,
	cfg *serviceConfig,
	provider string,
	code string,
	verifier string,
	redirectURI string,
) (string, error) {
	provider = normalizeMobileProvider(provider)
	code = strings.TrimSpace(code)
	verifier = strings.TrimSpace(verifier)
	redirectURI = strings.TrimSpace(redirectURI)
	if code == "" {
		return "", errMobileAuthInvalid
	}

	switch provider {
	case "discord":
		return exchangeDiscordOAuthToken(ctx, cfg, code, redirectURI)
	case "snapchat":
		return exchangeSnapchatOAuthToken(ctx, cfg, code, verifier, redirectURI)
	case "facebook":
		return exchangeFacebookOAuthToken(ctx, cfg, code, redirectURI)
	case "tiktok":
		return exchangeTikTokOAuthToken(ctx, cfg, code, verifier, redirectURI)
	default:
		return "", errMobileProviderUnsupported
	}
}
