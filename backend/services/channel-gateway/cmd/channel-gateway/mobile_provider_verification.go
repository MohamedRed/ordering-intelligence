package main

import (
	"context"
	"errors"
	"strings"
)

var (
	errMobileProviderTokenMissing = errors.New("mobile_provider_token_missing")
	errMobileProviderUnsupported  = errors.New("mobile_provider_unsupported")
)

type mobileProviderProfile struct {
	Provider    string
	Subject     string
	DisplayName string
}

func verifyMobileProvider(
	ctx context.Context,
	cfg *serviceConfig,
	provider string,
	accessToken string,
) (mobileProviderProfile, error) {
	provider = normalizeMobileProvider(provider)
	accessToken = strings.TrimSpace(accessToken)
	if provider == "" {
		return mobileProviderProfile{}, errMobileProviderUnsupported
	}
	if accessToken == "" {
		return mobileProviderProfile{}, errMobileProviderTokenMissing
	}
	if !isAllowedMobileProvider(provider) {
		return mobileProviderProfile{}, errMobileProviderUnsupported
	}

	switch provider {
	case "discord":
		user, err := fetchDiscordUser(ctx, cfg, accessToken)
		if err != nil {
			return mobileProviderProfile{}, err
		}
		name := strings.TrimSpace(user.GlobalName)
		if name == "" {
			name = strings.TrimSpace(user.Username)
		}
		return mobileProviderProfile{Provider: provider, Subject: strings.TrimSpace(user.ID), DisplayName: name}, nil
	case "snapchat":
		user, err := fetchSnapchatUser(ctx, cfg, accessToken)
		if err != nil {
			return mobileProviderProfile{}, err
		}
		return mobileProviderProfile{Provider: provider, Subject: strings.TrimSpace(user.ExternalID), DisplayName: strings.TrimSpace(user.DisplayName)}, nil
	case "facebook":
		user, err := fetchFacebookUser(ctx, cfg, accessToken)
		if err != nil {
			return mobileProviderProfile{}, err
		}
		return mobileProviderProfile{Provider: provider, Subject: strings.TrimSpace(user.ID), DisplayName: strings.TrimSpace(user.Name)}, nil
	case "tiktok":
		user, err := fetchTikTokUser(ctx, cfg, accessToken)
		if err != nil {
			return mobileProviderProfile{}, err
		}
		return mobileProviderProfile{Provider: provider, Subject: strings.TrimSpace(user.OpenID), DisplayName: strings.TrimSpace(user.DisplayName)}, nil
	default:
		return mobileProviderProfile{}, errMobileProviderUnsupported
	}
}
