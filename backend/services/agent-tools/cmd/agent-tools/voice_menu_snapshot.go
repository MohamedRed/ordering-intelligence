package main

import (
	"fmt"
	"sort"
	"strings"
)

type orderMenuSnapshot struct {
	StoreID string     `json:"storeId"`
	Items   []menuItem `json:"items"`
	Updated string     `json:"updated"`
}

type menuItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	PriceCents  int    `json:"priceCents"`
	Available   bool   `json:"available"`
	Category    string `json:"category"`
	Description string `json:"description"`
}

type voiceMenuSnapshot struct {
	StoreID         string              `json:"storeId"`
	MenuVersion     string              `json:"menuVersion"`
	Updated         string              `json:"updated,omitempty"`
	Locale          string              `json:"locale"`
	Currency        string              `json:"currency"`
	Model           string              `json:"model,omitempty"`
	PromptVersion   string              `json:"promptVersion,omitempty"`
	SummaryFR       string              `json:"summaryFr"`
	SpokenMenuFr    string              `json:"spokenMenuFr"`
	SuggestedFlowFr []string            `json:"suggestedFlowFr"`
	Categories      []voiceMenuCategory `json:"categories"`
}

type voiceMenuCategory struct {
	Name  string          `json:"name"`
	Items []voiceMenuItem `json:"items"`
}

type voiceMenuItem struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	Available     bool   `json:"available"`
	Description   string `json:"description,omitempty"`
	PriceCents    int    `json:"priceCents"`
	PriceDisplay  string `json:"priceDisplay"`
	PriceSpeechFR string `json:"priceSpeechFr"`
}

func buildVoiceMenuSnapshot(snap orderMenuSnapshot) voiceMenuSnapshot {
	byCat := make(map[string][]voiceMenuItem)
	for _, it := range snap.Items {
		cat := strings.TrimSpace(it.Category)
		if cat == "" {
			cat = "Menu"
		}
		v := voiceMenuItem{
			ID:            strings.TrimSpace(it.ID),
			Name:          strings.TrimSpace(it.Name),
			Available:     it.Available,
			Description:   strings.TrimSpace(it.Description),
			PriceCents:    it.PriceCents,
			PriceDisplay:  formatEURFr(it.PriceCents),
			PriceSpeechFR: speakEURFr(it.PriceCents),
		}
		byCat[cat] = append(byCat[cat], v)
	}

	cats := make([]string, 0, len(byCat))
	for k := range byCat {
		cats = append(cats, k)
	}
	sort.Strings(cats)

	outCats := make([]voiceMenuCategory, 0, len(cats))
	totalItems := 0
	for _, c := range cats {
		items := byCat[c]
		sort.Slice(items, func(i, j int) bool {
			return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
		})
		for i := range items {
			if strings.TrimSpace(items[i].Description) == "" {
				items[i].Description = ""
			}
		}
		outCats = append(outCats, voiceMenuCategory{Name: c, Items: items})
		totalItems += len(items)
	}

	summary := fmt.Sprintf("Menu chargé: %d article(s), %d catégorie(s). Pour annoncer le menu, présente d'abord les catégories, puis propose 3 à 5 options populaires et demande les préférences du client.", totalItems, len(outCats))

	return voiceMenuSnapshot{
		StoreID:    snap.StoreID,
		Updated:    snap.Updated,
		Locale:     "fr-FR",
		Currency:   "EUR",
		SummaryFR:  summary,
		Categories: outCats,
	}
}

func formatEURFr(priceCents int) string {
	if priceCents <= 0 {
		return "Gratuit"
	}
	euros := priceCents / 100
	cents := priceCents % 100
	return fmt.Sprintf("%s,%02d €", formatIntWithSpaces(euros), cents)
}

func formatIntWithSpaces(n int) string {
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	var b strings.Builder
	pre := len(s) % 3
	if pre == 0 {
		pre = 3
	}
	b.WriteString(s[:pre])
	for i := pre; i < len(s); i += 3 {
		b.WriteString(" ")
		b.WriteString(s[i : i+3])
	}
	return b.String()
}

func speakEURFr(priceCents int) string {
	if priceCents <= 0 {
		return "gratuit"
	}
	euros := priceCents / 100
	cents := priceCents % 100

	euroWord := "euros"
	if euros == 1 {
		euroWord = "euro"
	}
	if cents == 0 {
		return fmt.Sprintf("%s %s", frenchWords(euros), euroWord)
	}

	centWord := "centimes"
	if cents == 1 {
		centWord = "centime"
	}

	if cents >= 10 {
		return fmt.Sprintf("%s %s %s", frenchWords(euros), euroWord, frenchWords(cents))
	}
	return fmt.Sprintf("%s %s et %s %s", frenchWords(euros), euroWord, frenchWords(cents), centWord)
}

func frenchWords(n int) string {
	if n < 0 {
		return "moins " + frenchWords(-n)
	}
	if n == 0 {
		return "zéro"
	}
	if n < 100 {
		return frenchWordsUnder100(n)
	}
	if n < 1000 {
		h := n / 100
		r := n % 100
		if h == 1 {
			if r == 0 {
				return "cent"
			}
			return "cent " + frenchWordsUnder100(r)
		}
		if r == 0 {
			return frenchWordsUnder100(h) + " cents"
		}
		return frenchWordsUnder100(h) + " cent " + frenchWordsUnder100(r)
	}
	if n < 1_000_000 {
		th := n / 1000
		r := n % 1000
		var left string
		if th == 1 {
			left = "mille"
		} else {
			left = frenchWords(th) + " mille"
		}
		if r == 0 {
			return left
		}
		return left + " " + frenchWords(r)
	}
	if n < 1_000_000_000 {
		m := n / 1_000_000
		r := n % 1_000_000
		mw := "millions"
		if m == 1 {
			mw = "million"
		}
		left := frenchWords(m) + " " + mw
		if r == 0 {
			return left
		}
		return left + " " + frenchWords(r)
	}
	return fmt.Sprintf("%d", n)
}

func frenchWordsUnder100(n int) string {
	units := map[int]string{
		0:  "zéro",
		1:  "un",
		2:  "deux",
		3:  "trois",
		4:  "quatre",
		5:  "cinq",
		6:  "six",
		7:  "sept",
		8:  "huit",
		9:  "neuf",
		10: "dix",
		11: "onze",
		12: "douze",
		13: "treize",
		14: "quatorze",
		15: "quinze",
		16: "seize",
	}
	if n <= 16 {
		return units[n]
	}
	if n < 20 {
		switch n {
		case 17:
			return "dix-sept"
		case 18:
			return "dix-huit"
		case 19:
			return "dix-neuf"
		}
	}
	tens := map[int]string{
		20: "vingt",
		30: "trente",
		40: "quarante",
		50: "cinquante",
		60: "soixante",
		80: "quatre-vingt",
	}
	if n < 70 {
		t := (n / 10) * 10
		u := n % 10
		if u == 0 {
			return tens[t]
		}
		if u == 1 {
			return tens[t] + " et un"
		}
		return tens[t] + "-" + units[u]
	}
	if n < 80 {
		if n == 71 {
			return "soixante et onze"
		}
		return "soixante-" + frenchWordsUnder100(n-60)
	}
	r := n - 80
	if r == 0 {
		return "quatre-vingts"
	}
	if r == 1 {
		return "quatre-vingt-un"
	}
	if r <= 16 {
		return "quatre-vingt-" + units[r]
	}
	if r < 20 {
		return "quatre-vingt-" + frenchWordsUnder100(r)
	}
	return "quatre-vingt-" + frenchWordsUnder100(r)
}
