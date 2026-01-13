import Foundation

struct WatchFuelPaymentPlan {
  let amountCents: Int
  let paymentFlow: String
  let requestedAmountCents: Int
  let requestedLiters: Double
  let preauthAmountCents: Int
}

func resolveFuelPreauthCap(session: WatchSessionInfo?, fallbackCents: Int) -> Int {
  if let cap = session?.fuelPreauthCapCents, cap > 0 { return cap }
  if let storeCap = session?.fuelDefaultPrepayCents, storeCap > 0 { return storeCap }
  return fallbackCents
}

func resolveFuelPaymentPlan(
  fuel: WatchFuelOrder,
  preauthCapCents: Int
) -> WatchFuelPaymentPlan? {
  var paymentFlow = (fuel.paymentFlow ?? "prepay").lowercased()
  var requestedAmount = fuel.requestedAmountCents ?? 0
  let requestedLiters = fuel.requestedLiters ?? 0
  let unitPrice = fuel.unitPriceCents ?? 0
  var preauthAmount = fuel.preauthAmountCents ?? 0

  if paymentFlow == "preauth" && preauthAmount <= 0 {
    preauthAmount = preauthCapCents
  }
  if paymentFlow != "preauth" && requestedAmount <= 0 && requestedLiters <= 0 {
    paymentFlow = "preauth"
    preauthAmount = preauthCapCents
  }
  if paymentFlow == "preauth" {
    guard preauthAmount > 0 else { return nil }
    return WatchFuelPaymentPlan(
      amountCents: preauthAmount,
      paymentFlow: "preauth",
      requestedAmountCents: 0,
      requestedLiters: requestedLiters,
      preauthAmountCents: preauthAmount
    )
  }
  let amountCents: Int
  if requestedAmount > 0 {
    amountCents = requestedAmount
  } else if requestedLiters > 0 && unitPrice > 0 {
    amountCents = Int((requestedLiters * Double(unitPrice)).rounded())
  } else {
    return nil
  }
  return WatchFuelPaymentPlan(
    amountCents: amountCents,
    paymentFlow: paymentFlow,
    requestedAmountCents: requestedAmount,
    requestedLiters: requestedLiters,
    preauthAmountCents: 0
  )
}

func buildFuelPayload(
  fuel: WatchFuelOrder,
  plan: WatchFuelPaymentPlan
) -> [String: Any] {
  return [
    "fuelGradeId": fuel.fuelGradeId,
    "fuelGradeName": fuel.fuelGradeName ?? "",
    "unit": "liter",
    "unitPriceCents": fuel.unitPriceCents ?? 0,
    "requestedAmountCents": plan.requestedAmountCents,
    "requestedLiters": plan.requestedLiters,
    "preauthAmountCents": plan.preauthAmountCents,
    "paymentFlow": plan.paymentFlow
  ]
}
