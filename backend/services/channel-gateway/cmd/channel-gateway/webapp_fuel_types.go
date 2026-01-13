package main

type webAppFuelOrder struct {
	FuelGradeID          string  `json:"fuelGradeId"`
	FuelGradeName        string  `json:"fuelGradeName,omitempty"`
	Unit                string  `json:"unit,omitempty"`
	UnitPriceCents       int64   `json:"unitPriceCents,omitempty"`
	RequestedLiters      float64 `json:"requestedLiters,omitempty"`
	RequestedAmountCents int64   `json:"requestedAmountCents,omitempty"`
	PreauthAmountCents   int64   `json:"preauthAmountCents,omitempty"`
	PaymentFlow          string  `json:"paymentFlow,omitempty"`
	PumpNumber           string  `json:"pumpNumber,omitempty"`
}

type orderServiceFuelOrder struct {
	FuelGradeID          string  `json:"fuelGradeId"`
	FuelGradeName        string  `json:"fuelGradeName,omitempty"`
	Unit                string  `json:"unit,omitempty"`
	UnitPriceCents       int64   `json:"unitPriceCents,omitempty"`
	RequestedLiters      float64 `json:"requestedLiters,omitempty"`
	RequestedAmountCents int64   `json:"requestedAmountCents,omitempty"`
	PreauthAmountCents   int64   `json:"preauthAmountCents,omitempty"`
	PaymentFlow          string  `json:"paymentFlow,omitempty"`
	PumpNumber           string  `json:"pumpNumber,omitempty"`
}
