package main

type fuelOrderRequest struct {
	FuelGradeID         string  `json:"fuelGradeId"`
	FuelGradeName       string  `json:"fuelGradeName,omitempty"`
	Unit               string  `json:"unit,omitempty"`
	UnitPriceCents      int64   `json:"unitPriceCents,omitempty"`
	RequestedLiters     float64 `json:"requestedLiters,omitempty"`
	RequestedAmountCents int64  `json:"requestedAmountCents,omitempty"`
	PreauthAmountCents  int64   `json:"preauthAmountCents,omitempty"`
	PaymentFlow         string  `json:"paymentFlow,omitempty"`
	PumpNumber          string  `json:"pumpNumber,omitempty"`
}

type fuelOrder struct {
	FuelGradeID          string   `json:"fuelGradeId" firestore:"fuelGradeId"`
	FuelGradeName        string   `json:"fuelGradeName" firestore:"fuelGradeName"`
	Unit                string   `json:"unit" firestore:"unit"`
	UnitPriceCents       int64    `json:"unitPriceCents" firestore:"unitPriceCents"`
	RequestedLiters      float64  `json:"requestedLiters,omitempty" firestore:"requestedLiters,omitempty"`
	RequestedAmountCents int64    `json:"requestedAmountCents,omitempty" firestore:"requestedAmountCents,omitempty"`
	PreauthAmountCents   int64    `json:"preauthAmountCents,omitempty" firestore:"preauthAmountCents,omitempty"`
	PaymentFlow          string   `json:"paymentFlow" firestore:"paymentFlow"`
	PumpNumber           string   `json:"pumpNumber,omitempty" firestore:"pumpNumber,omitempty"`
	FinalLiters          float64  `json:"finalLiters,omitempty" firestore:"finalLiters,omitempty"`
	FinalAmountCents     int64    `json:"finalAmountCents,omitempty" firestore:"finalAmountCents,omitempty"`
	PaymentIntentID      string   `json:"paymentIntentId,omitempty" firestore:"paymentIntentId,omitempty"`
}

const (
	fuelUnitLiter        = "liter"
	fuelPaymentFlowPrepay  = "prepay"
	fuelPaymentFlowPreauth = "preauth"
)
