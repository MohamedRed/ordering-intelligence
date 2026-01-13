package main

import (
	"math"
	"strings"
)

func isGasStationBusinessType(businessType string) bool {
	return strings.EqualFold(strings.TrimSpace(businessType), "gas_station")
}

func roundFuelLiters(value float64) float64 {
	if value <= 0 {
		return 0
	}
	return math.Round(value*1000) / 1000
}

func findMenuItemByID(items []menuItem, id string) (menuItem, bool) {
	for _, item := range items {
		if strings.TrimSpace(item.ID) == id {
			return item, true
		}
	}
	return menuItem{}, false
}
