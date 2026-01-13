package com.orderingintelligence.auto

import kotlin.math.roundToInt
import org.json.JSONObject

data class AutoFuelPaymentPlan(
  val amountCents: Int,
  val paymentFlow: String,
  val requestedAmountCents: Int,
  val requestedLiters: Double,
  val preauthAmountCents: Int
)

fun resolveFuelPreauthCap(session: AutoSessionInfo?, fallbackCents: Int): Int {
  if (session != null) {
    if (session.fuelPreauthCapCents > 0) return session.fuelPreauthCapCents
    if (session.fuelDefaultPrepayCents > 0) return session.fuelDefaultPrepayCents
  }
  return fallbackCents
}

fun resolveFuelPaymentPlanForGrade(preauthCapCents: Int): AutoFuelPaymentPlan? {
  if (preauthCapCents <= 0) return null
  return AutoFuelPaymentPlan(
    amountCents = preauthCapCents,
    paymentFlow = "preauth",
    requestedAmountCents = 0,
    requestedLiters = 0.0,
    preauthAmountCents = preauthCapCents
  )
}

fun resolveFuelPaymentPlanForReorder(
  fuel: AutoFuelOrder,
  preauthCapCents: Int
): AutoFuelPaymentPlan? {
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
    return AutoFuelPaymentPlan(
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
  if (requestedAmount <= 0 && requestedLiters > 0 && unitPrice > 0) {
    requestedAmount = 0
  }
  return AutoFuelPaymentPlan(
    amountCents = amountCents,
    paymentFlow = paymentFlow,
    requestedAmountCents = requestedAmount,
    requestedLiters = requestedLiters,
    preauthAmountCents = 0
  )
}

fun buildFuelPayloadForGrade(
  grade: AutoMenuItem,
  plan: AutoFuelPaymentPlan
): JSONObject {
  return JSONObject()
    .put("fuelGradeId", grade.id)
    .put("fuelGradeName", grade.name)
    .put("unit", "liter")
    .put("unitPriceCents", grade.priceCents)
    .put("preauthAmountCents", plan.preauthAmountCents)
    .put("paymentFlow", plan.paymentFlow)
}

fun buildFuelPayloadForReorder(
  fuel: AutoFuelOrder,
  plan: AutoFuelPaymentPlan
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
