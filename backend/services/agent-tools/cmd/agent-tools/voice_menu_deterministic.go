package main

import (
	"fmt"
	"strings"
)

func defaultSuggestedFlowFr() []string {
	return []string{
		"Demander le type de repas: sur place ou à emporter, et la taille de faim.",
		"Proposer 2 à 3 catégories adaptées, puis 1 ou 2 options par catégorie.",
		"Demander les préférences: viande/poulet/végétarien, épicé ou non, et allergènes.",
		"Valider le choix et proposer un complément (boisson, dessert, sauce).",
	}
}

func deterministicSpokenMenuFr(menu voiceMenuSnapshot) string {
	// Short, safe script that never reads raw JSON and doesn’t require the agent to pronounce numbers.
	if len(menu.Categories) == 0 {
		return "Je n’ai pas trouvé de catégories de menu pour le moment. Que souhaitez-vous commander ?"
	}

	var catNames []string
	for _, c := range menu.Categories {
		if strings.TrimSpace(c.Name) != "" {
			catNames = append(catNames, strings.TrimSpace(c.Name))
		}
	}
	if len(catNames) == 0 {
		return "Je peux vous aider à commander. Vous cherchez plutôt un plat, une boisson, ou un dessert ?"
	}

	// Mention up to 3 categories, and one example item per category if available.
	maxCats := 3
	if len(menu.Categories) < maxCats {
		maxCats = len(menu.Categories)
	}

	var examples []string
	for i := 0; i < maxCats; i++ {
		c := menu.Categories[i]
		var ex string
		for _, it := range c.Items {
			if it.Available && strings.TrimSpace(it.Name) != "" {
				ex = fmt.Sprintf("%s à %s", strings.TrimSpace(it.Name), strings.TrimSpace(it.PriceSpeechFR))
				break
			}
		}
		if ex != "" {
			examples = append(examples, ex)
		}
	}

	catPart := strings.Join(catNames[:maxCats], ", ")
	if len(examples) > 0 {
		return fmt.Sprintf("Voici le menu: catégories %s. Par exemple: %s. Vous avez envie de quoi aujourd’hui ?", catPart, strings.Join(examples, ", "))
	}
	return fmt.Sprintf("Voici le menu: catégories %s. Vous avez envie de quoi aujourd’hui ?", catPart)
}
