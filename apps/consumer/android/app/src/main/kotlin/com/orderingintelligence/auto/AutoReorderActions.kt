package com.orderingintelligence.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast

fun handleFuelGradeClick(
  carContext: CarContext,
  sessionStore: AutoSessionStore,
  client: AutoClient,
  session: AutoSessionInfo?,
  grade: AutoMenuItem,
  hasDefaultPaymentMethod: Boolean,
  fallbackFuelPreauthCents: Int
) {
  val storeId = session?.storeId?.trim().orEmpty()
  if (storeId.isEmpty()) {
    CarToast.makeText(carContext, "Missing store selection", CarToast.LENGTH_SHORT).show()
    return
  }
  val cap = resolveFuelPreauthCap(session, fallbackFuelPreauthCents)
  val plan = resolveFuelPaymentPlanForGrade(cap)
  if (plan == null || !hasDefaultPaymentMethod) {
    val link = buildFuelHandoffLinkForGrade(
      storeId = storeId,
      grade = grade,
      amountCents = cap,
      currency = session?.currency,
      paymentFlow = "preauth"
    )
    sessionStore.saveHandoffLink(link)
    CarToast.makeText(carContext, "Open your phone to complete payment", CarToast.LENGTH_SHORT).show()
    return
  }
  val result = client.placeFuelOrder(
    storeId = storeId,
    fuel = buildFuelPayloadForGrade(grade, plan),
    amountCents = plan.amountCents,
    currency = session?.currency.orEmpty()
  )
  handleOffSessionResult(
    carContext = carContext,
    sessionStore = sessionStore,
    result = result,
    successMessage = "Fuel order placed"
  )
}

fun handleFuelReorderClick(
  carContext: CarContext,
  sessionStore: AutoSessionStore,
  client: AutoClient,
  order: AutoReorder,
  session: AutoSessionInfo?,
  hasDefaultPaymentMethod: Boolean,
  fallbackFuelPreauthCents: Int
) {
  val fuel = order.fuel ?: return
  val cap = resolveFuelPreauthCap(session, fallbackFuelPreauthCents)
  val plan = resolveFuelPaymentPlanForReorder(fuel, cap)
  if (plan == null || !hasDefaultPaymentMethod) {
    val handoff = buildFuelHandoffLinkForFuel(
      storeId = order.storeId,
      fuel = fuel,
      currency = order.currency
    )
    sessionStore.saveHandoffLink(handoff)
    CarToast.makeText(carContext, "Open your phone to complete payment", CarToast.LENGTH_SHORT).show()
    return
  }
  val currency = order.currency.ifBlank { session?.currency.orEmpty() }
  val result = client.placeFuelOrder(
    storeId = order.storeId,
    fuel = buildFuelPayloadForReorder(fuel, plan),
    amountCents = plan.amountCents,
    currency = currency
  )
  handleOffSessionResult(
    carContext = carContext,
    sessionStore = sessionStore,
    result = result,
    successMessage = "Fuel order placed"
  )
}

fun handleReorderClick(
  carContext: CarContext,
  sessionStore: AutoSessionStore,
  client: AutoClient,
  order: AutoReorder,
  hasDefaultPaymentMethod: Boolean
) {
  if (!hasDefaultPaymentMethod) {
    val handoff = buildReorderHandoffLink(order)
    sessionStore.saveHandoffLink(handoff)
    CarToast.makeText(carContext, "Open your phone to add a card", CarToast.LENGTH_SHORT).show()
    return
  }
  val result = client.placeReorder(order)
  handleOffSessionResult(
    carContext = carContext,
    sessionStore = sessionStore,
    result = result,
    successMessage = "Order placed"
  )
}

private fun handleOffSessionResult(
  carContext: CarContext,
  sessionStore: AutoSessionStore,
  result: AutoOrderPaymentResult,
  successMessage: String
) {
  when {
    result.payment.succeeded -> {
      CarToast.makeText(carContext, successMessage, CarToast.LENGTH_SHORT).show()
    }
    result.payment.requiresAction -> {
      val link = buildOrderPaymentHandoffLink(
        orderId = result.orderId,
        payment = result.payment
      )
      if (link != null) {
        sessionStore.saveHandoffLink(link)
        CarToast.makeText(carContext, "Open your phone to complete payment", CarToast.LENGTH_SHORT).show()
      } else {
        CarToast.makeText(carContext, "Payment needs phone confirmation", CarToast.LENGTH_SHORT).show()
      }
    }
    else -> {
      CarToast.makeText(
        carContext,
        result.payment.error ?: "Payment failed",
        CarToast.LENGTH_SHORT
      ).show()
    }
  }
}
