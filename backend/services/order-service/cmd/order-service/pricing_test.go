package main

import "testing"

func TestApplyMenuPricingUsesMenuPriceWhenZero(t *testing.T) {
	menu := map[string]menuItem{
		"a": {ID: "a", Name: "Burger", PriceCents: 900, Category: "mains"},
	}
	items := []orderItem{
		{ItemID: "a", Quantity: 1, PriceCents: 0},
	}
	out := applyMenuPricing(items, menu)
	if out[0].PriceCents != 900 {
		t.Fatalf("expected menu price 900, got %d", out[0].PriceCents)
	}
	if out[0].Name != "Burger" || out[0].Category != "mains" {
		t.Fatalf("expected name/category copied from menu")
	}
}

func TestApplyMenuPricingKeepsProvidedPrice(t *testing.T) {
	menu := map[string]menuItem{
		"a": {ID: "a", Name: "Burger", PriceCents: 900},
	}
	items := []orderItem{
		{ItemID: "a", Quantity: 1, PriceCents: 500},
	}
	out := applyMenuPricing(items, menu)
	if out[0].PriceCents != 500 {
		t.Fatalf("expected provided price preserved")
	}
}

func TestApplyMenuPricingPassesThroughUnknownItems(t *testing.T) {
	menu := map[string]menuItem{}
	items := []orderItem{
		{ItemID: "x", Quantity: 2, PriceCents: 700},
	}
	out := applyMenuPricing(items, menu)
	if out[0].ItemID != "x" || out[0].PriceCents != 700 {
		t.Fatalf("expected passthrough for unknown item")
	}
}
