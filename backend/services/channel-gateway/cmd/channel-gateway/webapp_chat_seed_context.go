package main

import (
	"fmt"
	"strings"
	"time"
)

type webappSeedContext struct {
	Intro      string
	Categories []string
	Source     string
}

func normalizeSeedContext(intro string, categories []string, source string) webappSeedContext {
	seed := webappSeedContext{
		Intro:      strings.TrimSpace(intro),
		Categories: normalizeSeedCategories(categories),
		Source:     strings.TrimSpace(source),
	}
	if seed.Source == "" {
		seed.Source = "menu"
	}
	return seed
}

func normalizeSeedCategories(input []string) []string {
	if len(input) == 0 {
		return nil
	}
	seen := map[string]struct{}{}
	out := make([]string, 0, len(input))
	for _, raw := range input {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, trimmed)
		if len(out) >= 10 {
			break
		}
	}
	return out
}

func (seed webappSeedContext) hasContent() bool {
	return strings.TrimSpace(seed.Intro) != "" || len(seed.Categories) > 0
}

func seedContextFromSession(session channelSession) webappSeedContext {
	return webappSeedContext{
		Intro:      strings.TrimSpace(session.SeededIntro),
		Categories: normalizeSeedCategories(session.SeededCategories),
		Source:     strings.TrimSpace(session.SeededSource),
	}
}

func applySeedContextToSession(session *channelSession, seed webappSeedContext) bool {
	if session == nil || !seed.hasContent() {
		return false
	}
	updated := false
	if seed.Intro != "" && seed.Intro != session.SeededIntro {
		session.SeededIntro = seed.Intro
		updated = true
	}
	if seed.Source != "" && seed.Source != session.SeededSource {
		session.SeededSource = seed.Source
		updated = true
	}
	if len(seed.Categories) > 0 {
		session.SeededCategories = seed.Categories
		updated = true
	}
	if updated {
		session.SeededAt = time.Now().UTC()
		session.SeededContextSent = false
	}
	return updated
}

func applySeedContextToDyn(dyn map[string]any, seed webappSeedContext) {
	if dyn == nil || !seed.hasContent() {
		return
	}
	if seed.Intro != "" {
		dyn["seeded_intro"] = seed.Intro
	}
	if len(seed.Categories) > 0 {
		dyn["seeded_categories"] = seed.Categories
	}
	if seed.Source != "" {
		dyn["seeded_source"] = seed.Source
	}
}

func seedContextPrefix(seed webappSeedContext) string {
	if !seed.hasContent() {
		return ""
	}
	parts := []string{
		"Contexte interne (ne pas afficher à l'utilisateur) : le chat a déjà démarré côté UI.",
	}
	if seed.Intro != "" {
		parts = append(parts, fmt.Sprintf("Message initial affiché : \"%s\".", seed.Intro))
	}
	if len(seed.Categories) > 0 {
		parts = append(parts, fmt.Sprintf("Catégories proposées : %s.", strings.Join(seed.Categories, ", ")))
	}
	parts = append(parts, "Ne pas saluer à nouveau. Réponds directement à la demande de l'utilisateur.")
	return strings.Join(parts, " ")
}

func looksLikeSeededGreeting(text string) bool {
	normalized := strings.ToLower(strings.TrimSpace(text))
	if normalized == "" {
		return false
	}
	if strings.Contains(normalized, "prêt à commander") || strings.Contains(normalized, "pret a commander") {
		return true
	}
	if strings.Contains(normalized, "temps d'attente") || strings.Contains(normalized, "temps d attente") {
		return true
	}
	if strings.Contains(normalized, "ready to order") || strings.Contains(normalized, "estimated wait") {
		return true
	}
	if len(normalized) > 140 {
		return false
	}
	return strings.HasPrefix(normalized, "bonjour") ||
		strings.HasPrefix(normalized, "salut") ||
		strings.HasPrefix(normalized, "hello") ||
		strings.HasPrefix(normalized, "hi ")
}
