package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	sharedconfig "github.com/ordering-intelligence/sharedconfig"
	"google.golang.org/api/option"
)

func loadConfig() (*serviceConfig, error) {
	values, err := sharedconfig.Load("channel-gateway", nil)
	if err != nil {
		return nil, err
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8090"
	}

	idleMinutes := intOrDefault(values["SESSION_IDLE_MINUTES"], 20)
	mobileSkew := intOrDefault(values["MOBILE_SESSION_MAX_SKEW_SECONDS"], 300)
	corsOrigins, err := parseCORSOrigins(stringOrDefault(values["CORS_ORIGINS"], ""))
	if err != nil {
		return nil, err
	}

	return &serviceConfig{
		Port:        port,
		Environment: stringOrDefault(values["ENVIRONMENT"], "development"),
		ProjectID:   stringOrDefault(values["FIRESTORE_PROJECT_ID"], ""),
		Credentials: stringOrDefault(values["GOOGLE_APPLICATION_CREDENTIALS"], ""),
		ElevenLabsAPIKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_API_KEY"),
			stringOrDefault(values["ELEVENLABS_API_KEY"], ""),
		)),
		ElevenLabsAPIBase: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_API_BASE_URL"),
			stringOrDefault(values["ELEVENLABS_API_BASE_URL"], "https://api.elevenlabs.io"),
		)),
		DefaultAgentID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ELEVENLABS_DEFAULT_AGENT_ID"),
			stringOrDefault(values["ELEVENLABS_DEFAULT_AGENT_ID"], ""),
		)),
		TelegramBotToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_BOT_TOKEN"),
			stringOrDefault(values["TELEGRAM_BOT_TOKEN"], ""),
		)),
		TelegramSecretToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_WEBHOOK_SECRET"),
			stringOrDefault(values["TELEGRAM_WEBHOOK_SECRET"], ""),
		)),
		TelegramBotUsername: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_BOT_USERNAME"),
			stringOrDefault(values["TELEGRAM_BOT_USERNAME"], ""),
		)),
		TelegramWebAppURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TELEGRAM_WEBAPP_URL"),
			stringOrDefault(values["TELEGRAM_WEBAPP_URL"], ""),
		)),
		DiscordClientID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_CLIENT_ID"),
			stringOrDefault(values["DISCORD_CLIENT_ID"], ""),
		)),
		DiscordClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_CLIENT_SECRET"),
			stringOrDefault(values["DISCORD_CLIENT_SECRET"], ""),
		)),
		DiscordPublicKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_PUBLIC_KEY"),
			stringOrDefault(values["DISCORD_PUBLIC_KEY"], ""),
		)),
		DiscordAPIBase: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_API_BASE_URL"),
			stringOrDefault(values["DISCORD_API_BASE_URL"], "https://discord.com/api/v10"),
		)),
		DiscordBotToken: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_BOT_TOKEN"),
			stringOrDefault(values["DISCORD_BOT_TOKEN"], ""),
		)),
		DiscordActivityChannelID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISCORD_ACTIVITY_CHANNEL_ID"),
			stringOrDefault(values["DISCORD_ACTIVITY_CHANNEL_ID"], ""),
		)),
		SnapchatClientID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_CLIENT_ID"),
			stringOrDefault(values["SNAPCHAT_CLIENT_ID"], ""),
		)),
		SnapchatClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_CLIENT_SECRET"),
			stringOrDefault(values["SNAPCHAT_CLIENT_SECRET"], ""),
		)),
		SnapchatAccountsBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_ACCOUNTS_BASE_URL"),
			stringOrDefault(values["SNAPCHAT_ACCOUNTS_BASE_URL"], "https://accounts.snapchat.com"),
		)),
		SnapchatAPIBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("SNAPCHAT_API_BASE_URL"),
			stringOrDefault(values["SNAPCHAT_API_BASE_URL"], "https://kit.snapchat.com"),
		)),
		FacebookAppID: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_APP_ID"),
			stringOrDefault(values["FACEBOOK_APP_ID"], ""),
		)),
		FacebookAppSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_APP_SECRET"),
			stringOrDefault(values["FACEBOOK_APP_SECRET"], ""),
		)),
		FacebookGraphBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("FACEBOOK_GRAPH_BASE_URL"),
			stringOrDefault(values["FACEBOOK_GRAPH_BASE_URL"], "https://graph.facebook.com"),
		)),
		TikTokClientKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_CLIENT_KEY"),
			stringOrDefault(values["TIKTOK_CLIENT_KEY"], ""),
		)),
		TikTokClientSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_CLIENT_SECRET"),
			stringOrDefault(values["TIKTOK_CLIENT_SECRET"], ""),
		)),
		TikTokAPIBaseURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TIKTOK_API_BASE_URL"),
			stringOrDefault(values["TIKTOK_API_BASE_URL"], "https://open.tiktokapis.com"),
		)),
		SessionIdleMinutes: idleMinutes,
		MobileSessionSecret: strings.TrimSpace(firstNonEmpty(
			os.Getenv("MOBILE_SESSION_SHARED_SECRET"),
			stringOrDefault(values["MOBILE_SESSION_SHARED_SECRET"], ""),
		)),
		MobileSessionSkewSeconds: mobileSkew,
		InternalAuthAudience: strings.TrimSpace(firstNonEmpty(
			os.Getenv("INTERNAL_AUTH_AUDIENCE"),
			stringOrDefault(values["INTERNAL_AUTH_AUDIENCE"], ""),
		)),
		InternalAllowedEmails: splitCSV(firstNonEmpty(
			os.Getenv("INTERNAL_ALLOWED_EMAILS"),
			stringOrDefault(values["INTERNAL_ALLOWED_EMAILS"], ""),
		)),
		OrderServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("ORDER_SERVICE_URL"),
			stringOrDefault(values["ORDER_SERVICE_URL"], ""),
		)),
		PaymentsServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("PAYMENTS_SERVICE_URL"),
			stringOrDefault(values["PAYMENTS_SERVICE_URL"], ""),
		)),
		DispatchServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("DISPATCH_SERVICE_URL"),
			stringOrDefault(values["DISPATCH_SERVICE_URL"], ""),
		)),
		CustomerProfileServiceURL: strings.TrimSpace(firstNonEmpty(
			os.Getenv("CUSTOMER_PROFILE_SERVICE_URL"),
			stringOrDefault(values["CUSTOMER_PROFILE_SERVICE_URL"], ""),
		)),
		TypesenseHost: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_HOST"),
			stringOrDefault(values["TYPESENSE_HOST"], ""),
		)),
		TypesenseAPIKey: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_SEARCH_API_KEY"),
			stringOrDefault(values["TYPESENSE_SEARCH_API_KEY"], ""),
		)),
		TypesenseCollection: strings.TrimSpace(firstNonEmpty(
			os.Getenv("TYPESENSE_COLLECTION"),
			stringOrDefault(values["TYPESENSE_COLLECTION"], "stores"),
		)),
		CORSOrigins: corsOrigins,
	}, nil
}

func newFirestoreClient(ctx context.Context, cfg *serviceConfig) (*cloudfirestore.Client, error) {
	if cfg.ProjectID == "" {
		return nil, fmt.Errorf("FIRESTORE_PROJECT_ID not configured")
	}
	var opts []option.ClientOption
	if cfg.Credentials != "" {
		opts = append(opts, option.WithCredentialsFile(cfg.Credentials))
	}
	return cloudfirestore.NewClient(ctx, cfg.ProjectID, opts...)
}
