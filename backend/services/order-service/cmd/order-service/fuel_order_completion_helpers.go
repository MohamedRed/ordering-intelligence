package main

import (
	"errors"
	"math"
)

func resolveFuelCompletionTotals(
	record *orderRecord,
	payload fuelCompleteRequest,
) (float64, int64, error) {
	finalLiters := payload.FinalLiters
	finalAmount := payload.FinalAmountCents
	unitPrice := record.Fuel.UnitPriceCents

	if finalAmount <= 0 && finalLiters > 0 && unitPrice > 0 {
		finalAmount = int64(math.Round(roundFuelLiters(finalLiters) * float64(unitPrice)))
	}
	if finalLiters <= 0 && finalAmount > 0 && unitPrice > 0 {
		finalLiters = roundFuelLiters(float64(finalAmount) / float64(unitPrice))
	}
	if finalAmount <= 0 {
		return 0, 0, errors.New("missing_final_amount")
	}

	switch record.Fuel.PaymentFlow {
	case fuelPaymentFlowPreauth:
		if record.Fuel.PreauthAmountCents > 0 &&
			finalAmount > record.Fuel.PreauthAmountCents {
			return 0, 0, errors.New("final_amount_exceeds_preauth")
		}
	case fuelPaymentFlowPrepay:
		if record.Fuel.RequestedAmountCents > 0 &&
			finalAmount != record.Fuel.RequestedAmountCents {
			return 0, 0, errors.New("final_amount_mismatch")
		}
	}

	return roundFuelLiters(finalLiters), finalAmount, nil
}
