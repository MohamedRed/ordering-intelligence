package main

import (
	"context"
	"log"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleTelegramInlineQuery(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
	accountID string,
	inline *telegramInlineQuery,
) {
	if inline == nil {
		writeJSON(w, http.StatusOK, map[string]string{"status": "inline_ignored"})
		return
	}
	if cfg.TelegramBotToken == "" {
		writeJSON(w, http.StatusOK, map[string]string{"status": "inline_disabled"})
		return
	}
	query := strings.TrimSpace(inline.Query)
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()

	webAppURL := resolveInlineWebAppURL(ctx, cfg, firestoreClient, accountID)
	if webAppURL == "" || len(query) < 2 {
		_ = answerTelegramInlineQuery(ctx, cfg.TelegramBotToken, telegramInlineQueryAnswer{
			InlineQueryID: inline.ID,
			Results:       []telegramInlineQueryResult{},
			CacheTime:     5,
			IsPersonal:    true,
		})
		writeJSON(w, http.StatusOK, map[string]string{"status": "inline_empty"})
		return
	}

	choices, err := searchStoreChoices(ctx, cfg, firestoreClient, query)
	if err != nil {
		log.Printf("inline store search failed account=%s err=%v", accountID, err)
	}
	botUsername := resolveTelegramBotUsername(ctx, cfg)
	results := buildInlineStoreResults(webAppURL, botUsername, choices)
	if err := answerTelegramInlineQuery(ctx, cfg.TelegramBotToken, telegramInlineQueryAnswer{
		InlineQueryID: inline.ID,
		Results:       results,
		CacheTime:     10,
		IsPersonal:    true,
	}); err != nil {
		log.Printf("inline answer failed account=%s err=%v", accountID, err)
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "inline_ok"})
}
