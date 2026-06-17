package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"golang.org/x/oauth2"
)

func handleVoiceMenuSnapshot(
	bg context.Context,
	cfg *serviceConfig,
	client *http.Client,
	tokenSrc oauth2.TokenSource,
	cache *voiceMenuCache,
	geminiGen *geminiGenerator,
	w http.ResponseWriter,
	r *http.Request,
) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if !requireScopes(r.Context(), w, "menu:read") {
		return
	}

	path := "/stores/" + url.PathEscape(storeID) + "/menu/snapshot"
	status, contentType, body, err := fetchFromOrderService(cfg, client, tokenSrc, r, http.MethodGet, path, nil)
	if err != nil {
		log.Printf("order-service menu snapshot fetch error: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "upstream_unavailable"})
		return
	}
	if status < 200 || status >= 300 {
		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
		return
	}

	var snap orderMenuSnapshot
	if err := json.Unmarshal(body, &snap); err != nil {
		log.Printf("menu snapshot parse failed; passing through raw response: %v", err)
		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
		return
	}

	voice := buildVoiceMenuSnapshot(snap)
	voice.MenuVersion = menuVersionForSnapshot(snap)
	voice.PromptVersion = voiceMenuPromptVersion
	if geminiGen != nil {
		voice.Model = geminiGen.Model()
	} else if strings.TrimSpace(cfg.GeminiModel) != "" {
		voice.Model = strings.TrimSpace(cfg.GeminiModel)
	}
	voice.SuggestedFlowFr = defaultSuggestedFlowFr()
	voice.SpokenMenuFr = deterministicSpokenMenuFr(voice)

	cacheKey := voiceMenuCacheKey(storeID, voice.MenuVersion, firstNonEmpty(voice.Model, "none"), voice.PromptVersion)
	cacheHit := false
	if cache != nil {
		if art, source, err := cache.GetScript(r.Context(), cacheKey); err == nil && art != nil {
			voice.SpokenMenuFr = art.SpokenMenuFr
			voice.SuggestedFlowFr = art.SuggestedFlowFr
			cacheHit = true
			log.Printf("voice_menu cache_hit source=%s store=%s version=%s", source, storeID, voice.MenuVersion)
		}
	}
	if !cacheHit {
		log.Printf("voice_menu cache_miss store=%s version=%s", storeID, voice.MenuVersion)
	}

	if geminiGen != nil && (strings.TrimSpace(voice.SpokenMenuFr) == "" || voice.SpokenMenuFr == deterministicSpokenMenuFr(voice)) {
		gctx, cancel := context.WithTimeout(r.Context(), 2500*time.Millisecond)
		start := time.Now()
		art, err := geminiGen.GenerateMenuScript(gctx, snap, voice)
		cancel()
		if err == nil && art != nil {
			voice.SpokenMenuFr = art.SpokenMenuFr
			voice.SuggestedFlowFr = art.SuggestedFlowFr
			log.Printf("voice_menu gemini_ok store=%s version=%s ms=%d", storeID, voice.MenuVersion, time.Since(start).Milliseconds())
			if cache != nil {
				_ = cache.PutScript(bg, cacheKey, voiceMenuCacheMeta(storeID, voice), *art)
			}
		} else if cache != nil {
			log.Printf("voice_menu gemini_err store=%s version=%s err=%v", storeID, voice.MenuVersion, err)
			go fillVoiceMenuCacheInBackground(cache, cacheKey, storeID, geminiGen, snap, voice)
		}
	}

	writeJSON(w, http.StatusOK, voice)
}

func fillVoiceMenuCacheInBackground(
	cache *voiceMenuCache,
	cacheKey string,
	storeID string,
	geminiGen *geminiGenerator,
	snap orderMenuSnapshot,
	voice voiceMenuSnapshot,
) {
	bctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	art, err := geminiGen.GenerateMenuScript(bctx, snap, voice)
	if err != nil || art == nil {
		return
	}
	_ = cache.PutScript(bctx, cacheKey, voiceMenuCacheMeta(storeID, voice), *art)
}

func voiceMenuCacheMeta(storeID string, voice voiceMenuSnapshot) map[string]any {
	return map[string]any{
		"store_id":       storeID,
		"menu_version":   voice.MenuVersion,
		"model":          voice.Model,
		"prompt_version": voice.PromptVersion,
	}
}
