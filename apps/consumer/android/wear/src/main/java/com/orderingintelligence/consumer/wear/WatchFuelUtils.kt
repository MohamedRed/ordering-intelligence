package com.orderingintelligence.consumer.wear

import kotlin.math.roundToInt
import org.json.JSONObject

data class WatchFuelPaymentPlan(
  val amountCents: Int,
  val paymentFlow: String,
  val requestedAmountCents: Int,
  val requestedLiters: Double,
  val preauthAmountCents: Int
)

fun resolveFuelPreauthCap(session: WatchSessionInfo?, fallbackCents: Int): Int {
  if (session != null) {
    if (session.fuelPreauthCapCents > 0) return session.fuelPreauthCapCents
    if (session.fuelDefaultPrepayCents > 0) return session.fuelDefaultPrepayCents
  }
  return fallbackCents
}

fun resolveFuelPaymentPlan(
  fuel: WatchFuelOrder,
  preauthCapCents: Int
): WatchFuelPaymentPlan? {
  var paymentFlow = fuel.paymentFlow.ifBlank { "prepay" }.lowercase()
  var requestedAmount = fuel.requestedAmountCents
  val requestedLiters = fuel.requestedLiters
  val unitPrice = fuel.unitPriceCents
  var preauthAmount = fuel.preauthAmountCents

  if (paymentFlow == "preauth" && preauthAmount <= 0) {
    preauthAmount = preauthCapCents
  }
  if (paymentFlow != "preauth" && requestedAmount <= 0 && requestedLiters <= 0) {
    paymentFlow = "preauth"
    preauthAmount = preauthCapCents
  }
  if (paymentFlow == "preauth") {
    if (preauthAmount <= 0) return null
    return WatchFuelPaymentPlan(
      amountCents = preauthAmount,
      paymentFlow = "preauth",
      requestedAmountCents = 0,
      requestedLiters = requestedLiters,
      preauthAmountCents = preauthAmount
    )
  }
  val amountCents = when {
    requestedAmount > 0 -> requestedAmount
    requestedLiters > 0 && unitPrice > 0 -> (requestedLiters * unitPrice).roundToInt()
    else -> return null
  }
  return WatchFuelPaymentPlan(
    amountCents = amountCents,
    paymentFlow = paymentFlow,
    requestedAmountCents = requestedAmount,
    requestedLiters = requestedLiters,
    preauthAmountCents = 0
  )
}

fun buildFuelPayload(
  fuel: WatchFuelOrder,
  plan: WatchFuelPaymentPlan
): JSONObject {
  return JSONObject()
    .put("fuelGradeId", fuel.fuelGradeId)
    .put("fuelGradeName", fuel.fuelGradeName)
    .put("unit", "liter")
    .put("unitPriceCents", fuel.unitPriceCents)
    .put("requestedAmountCents", plan.requestedAmountCents)
    .put("requestedLiters", plan.requestedLiters)
    .put("preauthAmountCents", plan.preauthAmountCents)
    .put("paymentFlow", plan.paymentFlow)
}
