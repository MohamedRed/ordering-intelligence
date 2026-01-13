package main

import (
	"errors"
	"math"
	"strings"
)

func normalizeFuelOrder(
	menu menuRecord,
	req fuelOrderRequest,
) (fuelOrder, totals, error) {
	gradeID := strings.TrimSpace(req.FuelGradeID)
	if gradeID == "" {
		return fuelOrder{}, totals{}, errors.New("missing_fuel_grade")
	}
	unit := strings.ToLower(strings.TrimSpace(req.Unit))
	if unit == "" {
		unit = fuelUnitLiter
	}
	if unit != fuelUnitLiter {
		return fuelOrder{}, totals{}, errors.New("unsupported_fuel_unit")
	}
	paymentFlow := strings.ToLower(strings.TrimSpace(req.PaymentFlow))
	if paymentFlow == "" {
		paymentFlow = fuelPaymentFlowPrepay
	}
	if paymentFlow != fuelPaymentFlowPrepay && paymentFlow != fuelPaymentFlowPreauth {
		return fuelOrder{}, totals{}, errors.New("invalid_payment_flow")
	}

	menuItem, ok := findMenuItemByID(menu.Items, gradeID)
	if !ok {
		return fuelOrder{}, totals{}, errors.New("fuel_grade_not_found")
	}
	gradeName := strings.TrimSpace(req.FuelGradeName)
	if gradeName == "" {
		gradeName = strings.TrimSpace(menuItem.Name)
	}
	unitPrice := req.UnitPriceCents
	if unitPrice <= 0 {
		unitPrice = menuItem.PriceCents
	}
	if unitPrice <= 0 {
		return fuelOrder{}, totals{}, errors.New("invalid_unit_price")
	}

	requestedLiters := req.RequestedLiters
	requestedAmount := req.RequestedAmountCents
	preauthAmount := req.PreauthAmountCents

	switch paymentFlow {
	case fuelPaymentFlowPrepay:
		if requestedAmount <= 0 && requestedLiters <= 0 {
			return fuelOrder{}, totals{}, errors.New("missing_fuel_amount")
		}
		if requestedAmount <= 0 && requestedLiters > 0 {
			requestedAmount = int64(math.Round(requestedLiters * float64(unitPrice)))
		}
		if requestedLiters <= 0 && requestedAmount > 0 {
			requestedLiters = roundFuelLiters(float64(requestedAmount) / float64(unitPrice))
		}
	case fuelPaymentFlowPreauth:
		if preauthAmount <= 0 {
			return fuelOrder{}, totals{}, errors.New("missing_preauth_amount")
		}
	}

	fuel := fuelOrder{
		FuelGradeID:          gradeID,
		FuelGradeName:        gradeName,
		Unit:                unit,
		UnitPriceCents:       unitPrice,
		RequestedLiters:      roundFuelLiters(requestedLiters),
		RequestedAmountCents: requestedAmount,
		PreauthAmountCents:   preauthAmount,
		PaymentFlow:          paymentFlow,
		PumpNumber:           strings.TrimSpace(req.PumpNumber),
	}

	totalCents := requestedAmount
	if paymentFlow == fuelPaymentFlowPreauth {
		totalCents = preauthAmount
	}

	return fuel, totals{
		SubtotalCents: totalCents,
		TotalCents:    totalCents,
	}, nil
}
