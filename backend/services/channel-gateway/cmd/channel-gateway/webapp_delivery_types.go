package main

import "strings"

type webAppDelivery struct {
	FleetMode      string                 `json:"fleetMode,omitempty"`
	DropoffLatLng  *webAppDeliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress *webAppDeliveryAddress `json:"dropoffAddress,omitempty"`
	Instructions   string                 `json:"instructions,omitempty"`
	OfferCents     int64                  `json:"offerCents,omitempty"`
}

type webAppDeliveryLatLng struct {
	Lat float64 `json:"lat,omitempty"`
	Lng float64 `json:"lng,omitempty"`
}

type webAppDeliveryAddress struct {
	Line1      string `json:"line1,omitempty"`
	Line2      string `json:"line2,omitempty"`
	City       string `json:"city,omitempty"`
	State      string `json:"state,omitempty"`
	PostalCode string `json:"postalCode,omitempty"`
	Country    string `json:"country,omitempty"`
	Formatted  string `json:"formatted,omitempty"`
}

type orderServiceDelivery struct {
	FleetMode      string                 `json:"fleetMode,omitempty"`
	DropoffLatLng  *webAppDeliveryLatLng  `json:"dropoffLatLng,omitempty"`
	DropoffAddress *webAppDeliveryAddress `json:"dropoffAddress,omitempty"`
	Instructions   string                 `json:"instructions,omitempty"`
	OfferCents     int64                  `json:"offerCents,omitempty"`
}

func buildOrderServiceDelivery(input *webAppDelivery) *orderServiceDelivery {
	if input == nil {
		return nil
	}
	fleet := strings.ToLower(strings.TrimSpace(input.FleetMode))
	out := &orderServiceDelivery{
		FleetMode:    fleet,
		Instructions: strings.TrimSpace(input.Instructions),
		OfferCents:   input.OfferCents,
	}
	if input.DropoffLatLng != nil {
		out.DropoffLatLng = &webAppDeliveryLatLng{
			Lat: input.DropoffLatLng.Lat,
			Lng: input.DropoffLatLng.Lng,
		}
	}
	if input.DropoffAddress != nil {
		out.DropoffAddress = &webAppDeliveryAddress{
			Line1:      strings.TrimSpace(input.DropoffAddress.Line1),
			Line2:      strings.TrimSpace(input.DropoffAddress.Line2),
			City:       strings.TrimSpace(input.DropoffAddress.City),
			State:      strings.TrimSpace(input.DropoffAddress.State),
			PostalCode: strings.TrimSpace(input.DropoffAddress.PostalCode),
			Country:    strings.TrimSpace(input.DropoffAddress.Country),
			Formatted:  strings.TrimSpace(input.DropoffAddress.Formatted),
		}
	}
	return out
}
