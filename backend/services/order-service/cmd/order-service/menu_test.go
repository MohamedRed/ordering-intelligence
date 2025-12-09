package main

import (
	"sync"
	"testing"
	"time"
)

func TestValidateMenuItemsOK(t *testing.T) {
	items := []menuItem{
		{ID: "1", Name: "Burger", PriceCents: 1000, Available: true},
	}
	if err := validateMenuItems(items); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}

func TestValidateMenuItemsMissingName(t *testing.T) {
	items := []menuItem{
		{ID: "1", Name: "", PriceCents: 500, Available: true},
	}
	if err := validateMenuItems(items); err == nil {
		t.Fatalf("expected error for missing name")
	}
}

func TestValidateMenuItemsMissingID(t *testing.T) {
	items := []menuItem{
		{ID: "", Name: "Test", PriceCents: 500, Available: true},
	}
	if err := validateMenuItems(items); err == nil {
		t.Fatalf("expected error for missing id")
	}
}

func TestValidateMenuItemsNegativePrice(t *testing.T) {
	items := []menuItem{
		{ID: "1", Name: "Test", PriceCents: -5, Available: true},
	}
	if err := validateMenuItems(items); err == nil {
		t.Fatalf("expected error for negative price")
	}
}

func TestValidateMenuItemsUnavailableZeroPrice(t *testing.T) {
	items := []menuItem{
		{ID: "1", Name: "Test", PriceCents: 0, Available: false},
	}
	if err := validateMenuItems(items); err == nil {
		t.Fatalf("expected error for zero price unavailable item")
	}
}

func TestParseIntDefault(t *testing.T) {
	if got := parseIntDefault("", 5); got != 5 {
		t.Fatalf("expected fallback on empty")
	}
	if got := parseIntDefault("notint", 5); got != 5 {
		t.Fatalf("expected fallback on bad int")
	}
	if got := parseIntDefault("7", 5); got != 7 {
		t.Fatalf("expected parsed int")
	}
}

func TestInvalidateMenuCache(t *testing.T) {
	menuCache = sync.Map{}
	menuCache.Store("s1", cachedMenu{menu: &menuRecord{StoreID: "s1"}, expires: time.Now().Add(time.Minute)})
	invalidateMenuCache("s1")
	if _, ok := menuCache.Load("s1"); ok {
		t.Fatalf("expected cache cleared")
	}
}
