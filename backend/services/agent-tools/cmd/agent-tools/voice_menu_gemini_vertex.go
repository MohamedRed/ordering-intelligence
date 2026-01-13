package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

type geminiGenerator struct {
	client   *http.Client
	project  string
	location string
	model    string
}

func newGeminiGenerator(ctx context.Context, cfg *serviceConfig) (*geminiGenerator, error) {
	if strings.TrimSpace(cfg.ProjectID) == "" || strings.TrimSpace(cfg.VertexLocation) == "" || strings.TrimSpace(cfg.GeminiModel) == "" {
		return nil, nil
	}
	ts, err := google.DefaultTokenSource(ctx, "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		return nil, err
	}
	httpClient := oauth2.NewClient(ctx, ts)
	return &geminiGenerator{
		client:   httpClient,
		project:  strings.TrimSpace(cfg.ProjectID),
		location: strings.TrimSpace(cfg.VertexLocation),
		model:    strings.TrimSpace(cfg.GeminiModel),
	}, nil
}

func (g *geminiGenerator) Model() string { return g.model }

func (g *geminiGenerator) GenerateMenuScript(ctx context.Context, snap orderMenuSnapshot, voice voiceMenuSnapshot) (*voiceMenuScriptArtifact, error) {
	if g == nil {
		return nil, errors.New("gemini disabled")
	}

	// Keep payload small: per category include up to N items (available first).
	const maxItemsPerCategory = 12
	cats := make([]map[string]any, 0, len(voice.Categories))
	for _, c := range voice.Categories {
		items := make([]voiceMenuItem, 0, len(c.Items))
		items = append(items, c.Items...)
		sort.Slice(items, func(i, j int) bool {
			// Available first, then alphabetical.
			if items[i].Available != items[j].Available {
				return items[i].Available
			}
			return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
		})
		if len(items) > maxItemsPerCategory {
			items = items[:maxItemsPerCategory]
		}
		outItems := make([]map[string]any, 0, len(items))
		for _, it := range items {
			// Provide priceSpeechFr so the model doesn't have to reason about numbers.
			outItems = append(outItems, map[string]any{
				"id":            it.ID,
				"name":          it.Name,
				"available":     it.Available,
				"priceSpeechFr": it.PriceSpeechFR,
			})
		}
		cats = append(cats, map[string]any{
			"name":  c.Name,
			"items": outItems,
		})
	}

	input := map[string]any{
		"storeId":     voice.StoreID,
		"menuVersion": voice.MenuVersion,
		"locale":      "fr-FR",
		"currency":    "EUR",
		"categories":  cats,
		"instructions": map[string]any{
			"maxItemsToMentionTotal": 5,
			"tone":                   "friendly, concise, helpful",
			"avoidReadingJson":       true,
			"endWithAQuestion":       true,
		},
	}
	inputJSON, _ := json.Marshal(input)

	systemText := strings.TrimSpace(`
Tu génères un script de présentation de menu pour un assistant vocal de prise de commande.
Réponds en JSON STRICT uniquement (aucun texte hors JSON).
Ne lis jamais des champs techniques. N'énumère pas tout le menu.
Si tu mentionnes un article précis dans spokenMenuFr, ajoute son id dans mentionedItemIds.
N'invente pas d'articles. N'invente pas de prix. Utilise priceSpeechFr pour les prix.
`)

	userText := "Données du menu (JSON):\n" + string(inputJSON) + "\n\nRetourne JSON avec:\n- spokenMenuFr (string, 30-60s)\n- suggestedFlowFr (array of 3-6 short strings)\n- mentionedItemIds (optional array of ids)"

	reqBody := map[string]any{
		"systemInstruction": map[string]any{"parts": []map[string]any{{"text": systemText}}},
		"contents":          []map[string]any{{"role": "user", "parts": []map[string]any{{"text": userText}}}},
		"generationConfig": map[string]any{
			"temperature":      0.3,
			"maxOutputTokens":  900,
			"responseMimeType": "application/json",
		},
	}
	rawReq, _ := json.Marshal(reqBody)

	url := g.vertexGenerateContentURL()
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(rawReq))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")

	start := time.Now()
	resp, err := g.client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBytes, _ := io.ReadAll(resp.Body)
	_ = start

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("vertex non-2xx status=%d body=%s", resp.StatusCode, truncate(string(respBytes), 500))
	}

	text, err := extractVertexText(respBytes)
	if err != nil {
		return nil, err
	}

	// Strict JSON parsing.
	var art voiceMenuScriptArtifact
	if err := json.Unmarshal([]byte(text), &art); err != nil {
		return nil, fmt.Errorf("invalid json from model: %v", err)
	}
	art.SpokenMenuFr = strings.TrimSpace(art.SpokenMenuFr)
	if art.SpokenMenuFr == "" {
		return nil, errors.New("model returned empty spokenMenuFr")
	}
	// Hard guardrails: avoid numeric formatting bugs in French and prevent JSON-recital artifacts.
	if containsAnyDigit(art.SpokenMenuFr) {
		return nil, errors.New("model script contains digits; require fully-spelled prices")
	}
	lower := strings.ToLower(art.SpokenMenuFr)
	if strings.Contains(lower, "pricecents") || strings.Contains(lower, "modifiers") || strings.Contains(lower, "{") || strings.Contains(lower, "}") {
		return nil, errors.New("model script contains technical/json artifacts")
	}

	// Validate mentioned item IDs against the provided menu subset.
	allowed := make(map[string]bool)
	for _, c := range voice.Categories {
		for _, it := range c.Items {
			if strings.TrimSpace(it.ID) != "" && it.Available {
				allowed[strings.TrimSpace(it.ID)] = true
			}
		}
	}
	var mentioned []string
	for _, id := range art.MentionedItemIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if allowed[id] {
			mentioned = append(mentioned, id)
		}
		if len(mentioned) >= 8 {
			break
		}
	}
	art.MentionedItemIDs = mentioned

	// Normalize flow list.
	var flow []string
	for _, s := range art.SuggestedFlowFr {
		s = strings.TrimSpace(s)
		if s != "" {
			flow = append(flow, s)
		}
	}
	if len(flow) == 0 {
		flow = defaultSuggestedFlowFr()
	}
	art.SuggestedFlowFr = flow
	return &art, nil
}

func (g *geminiGenerator) vertexGenerateContentURL() string {
	// Allow either a short model ID (e.g. "gemini-...") or a full publisher path.
	model := strings.TrimSpace(g.model)
	if strings.HasPrefix(model, "publishers/") {
		return fmt.Sprintf("https://%s-aiplatform.googleapis.com/v1/projects/%s/locations/%s/%s:generateContent", g.location, g.project, g.location, model)
	}
	return fmt.Sprintf("https://%s-aiplatform.googleapis.com/v1/projects/%s/locations/%s/publishers/google/models/%s:generateContent", g.location, g.project, g.location, model)
}

func extractVertexText(resp []byte) (string, error) {
	// Vertex generateContent response: candidates[].content.parts[].text
	var parsed map[string]any
	if err := json.Unmarshal(resp, &parsed); err != nil {
		return "", err
	}
	cands, _ := parsed["candidates"].([]any)
	if len(cands) == 0 {
		return "", errors.New("no candidates")
	}
	first, _ := cands[0].(map[string]any)
	content, _ := first["content"].(map[string]any)
	parts, _ := content["parts"].([]any)
	for _, p := range parts {
		pm, _ := p.(map[string]any)
		if t, ok := pm["text"].(string); ok && strings.TrimSpace(t) != "" {
			return strings.TrimSpace(t), nil
		}
	}
	return "", errors.New("no text part in candidate")
}

func truncate(s string, max int) string {
	s = strings.TrimSpace(s)
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}

func containsAnyDigit(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			return true
		}
	}
	return false
}
