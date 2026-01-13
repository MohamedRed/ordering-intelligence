package main

import (
	"sort"
	"strings"
)

type orderMenuSnapshotFull struct {
	StoreID string         `json:"storeId"`
	Items   []menuItemFull `json:"items"`
	Updated string         `json:"updated"`
}

type menuItemFull struct {
	ID             string              `json:"id"`
	Name           string              `json:"name"`
	PriceCents     int                 `json:"priceCents"`
	Available      bool                `json:"available"`
	Category       string              `json:"category"`
	Description    string              `json:"description"`
	Modifiers      []legacyModifier    `json:"modifiers,omitempty"`
	ModifierGroups []menuModifierGroup `json:"modifierGroups,omitempty"`
}

type legacyModifier struct {
	Name       string `json:"name"`
	PriceCents int    `json:"priceCents"`
}

type menuModifierGroup struct {
	ID            string               `json:"id"`
	Name          string               `json:"name"`
	Required      bool                 `json:"required"`
	MinSelections int                  `json:"minSelections"`
	MaxSelections int                  `json:"maxSelections"`
	Options       []menuModifierOption `json:"options"`
}

type menuModifierOption struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	PriceCents int    `json:"priceCents"`
}

type menuSearchItem struct {
	ItemID         string              `json:"itemId"`
	Name           string              `json:"name"`
	Category       string              `json:"category"`
	PriceCents     int                 `json:"priceCents"`
	Available      bool                `json:"available"`
	Description    string              `json:"description,omitempty"`
	RequiredGroups []menuRequiredGroup `json:"requiredGroups,omitempty"`
}

type menuRequiredGroup struct {
	GroupID       string `json:"groupId"`
	Name          string `json:"name"`
	MinSelections int    `json:"minSelections"`
	MaxSelections int    `json:"maxSelections"`
}

func menuVersionForUpdated(updated string) string {
	if strings.TrimSpace(updated) != "" {
		return strings.TrimSpace(updated)
	}
	return "unknown"
}

func searchMenuItems(snap orderMenuSnapshotFull, query string, limit int) []menuSearchItem {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil
	}
	if limit <= 0 {
		limit = 10
	}

	type scored struct {
		item  menuSearchItem
		score int
	}
	scoredItems := make([]scored, 0, len(snap.Items))
	for _, it := range snap.Items {
		name := strings.TrimSpace(it.Name)
		cat := strings.TrimSpace(it.Category)
		nameLower := strings.ToLower(name)
		catLower := strings.ToLower(cat)

		score := 0
		if nameLower == q {
			score = 100
		} else if strings.HasPrefix(nameLower, q) {
			score = 80
		} else if strings.Contains(nameLower, q) {
			score = 60
		} else if strings.Contains(catLower, q) {
			score = 30
		} else if strings.Contains(strings.ToLower(strings.TrimSpace(it.Description)), q) {
			score = 20
		}
		if score == 0 {
			continue
		}

		reqGroups := requiredGroups(it.ModifierGroups)
		scoredItems = append(scoredItems, scored{
			item: menuSearchItem{
				ItemID:         strings.TrimSpace(it.ID),
				Name:           name,
				Category:       cat,
				PriceCents:     it.PriceCents,
				Available:      it.Available,
				Description:    strings.TrimSpace(it.Description),
				RequiredGroups: reqGroups,
			},
			score: score,
		})
	}

	sort.Slice(scoredItems, func(i, j int) bool {
		if scoredItems[i].score != scoredItems[j].score {
			return scoredItems[i].score > scoredItems[j].score
		}
		return strings.ToLower(scoredItems[i].item.Name) < strings.ToLower(scoredItems[j].item.Name)
	})

	out := make([]menuSearchItem, 0, minInt(limit, len(scoredItems)))
	for _, s := range scoredItems {
		out = append(out, s.item)
		if len(out) >= limit {
			break
		}
	}
	return out
}

func requiredGroups(groups []menuModifierGroup) []menuRequiredGroup {
	out := []menuRequiredGroup{}
	for _, g := range groups {
		minSel := g.MinSelections
		if g.Required && minSel == 0 {
			minSel = 1
		}
		if minSel <= 0 {
			continue
		}
		out = append(out, menuRequiredGroup{
			GroupID:       strings.TrimSpace(g.ID),
			Name:          strings.TrimSpace(g.Name),
			MinSelections: minSel,
			MaxSelections: g.MaxSelections,
		})
	}
	return out
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
