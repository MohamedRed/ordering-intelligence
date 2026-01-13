package main

import (
	"context"
	"fmt"
	"net/url"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/ordering-intelligence/agentcontext"
)

func resolveInlineWebAppURL(
	ctx context.Context,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	accountID string,
) string {
	base := strings.TrimSpace(cfg.TelegramWebAppURL)
	if accountID == "" || firestoreClient == nil {
		return base
	}
	route, err := agentcontext.ResolveRoute(ctx, firestoreClient, agentcontext.RouteLookup{
		Channel:          "telegram",
		ChannelAccountID: accountID,
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

func buildInlineStoreResults(baseURL, botUsername string, choices []storeChoice) []telegramInlineQueryResult {
	results := make([]telegramInlineQueryResult, 0, len(choices))
	for _, choice := range choices {
		orderURL := buildTelegramInlineURL(baseURL, botUsername, choice.StoreID, false)
		groupURL := buildTelegramInlineURL(baseURL, botUsername, choice.StoreID, true)
		if orderURL == "" || groupURL == "" {
			continue
		}
		id := hashCaller(choice.StoreID)
		results = append(results, telegramInlineQueryResult{
			Type:        "article",
			ID:          id,
			Title:       choice.Name,
			Description: "Choose order type",
			InputMessageContent: telegramInlineMessageContent{
				MessageText:           fmt.Sprintf("Choose an order type for %s", choice.Name),
				DisableWebPagePreview: true,
			},
			ReplyMarkup: &telegramInlineKeyboardMarkup{
				InlineKeyboard: [][]telegramInlineKeyboardButton{
					{
						{
							Text: "Order for me",
							URL:  orderURL,
						},
						{
							Text: "Start group order",
							URL:  groupURL,
						},
					},
				},
			},
		})
	}
	return results
}

func buildTelegramWebAppURL(baseURL, storeID string, startGroup bool) string {
	if strings.TrimSpace(baseURL) == "" {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil {
		return baseURL
	}
	params := parsed.Query()
	if strings.TrimSpace(storeID) != "" {
		params.Set("storeId", storeID)
	}
	if startGroup {
		params.Set("startGroupOrder", "1")
	}
	params.Set("source", "inline")
	parsed.RawQuery = params.Encode()
	return parsed.String()
}
