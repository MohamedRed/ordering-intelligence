package com.orderingintelligence.consumer.wear

import java.net.URLEncoder

object WatchHandoffLink {
  fun buildLink(order: WatchReorder): String {
    val fuel = order.fuel
    if (fuel != null) {
      return buildFuelLink(order.storeId, fuel, order.currency)
    }
    return buildReorderLink(order)
  }

  fun buildOrderPaymentLink(orderId: String, payment: WatchOffSessionResult): String? {
    val clientSecret = payment.clientSecret ?: return null
    val params = mutableListOf(
      "orderId=${encode(orderId)}",
      "clientSecret=${encode(clientSecret)}"
    )
    payment.paymentId?.let { if (it.isNotBlank()) params.add("paymentId=${encode(it)}") }
    payment.paymentIntentId?.let { if (it.isNotBlank()) params.add("paymentIntentId=${encode(it)}") }
    payment.customerId?.let { if (it.isNotBlank()) params.add("customerId=${encode(it)}") }
    payment.ephemeralKey?.let { if (it.isNotBlank()) params.add("ephemeralKey=${encode(it)}") }
    payment.stripeAccountId?.let { if (it.isNotBlank()) params.add("stripeAccountId=${encode(it)}") }
    payment.publishableKey?.let { if (it.isNotBlank()) params.add("publishableKey=${encode(it)}") }
    payment.amountCents?.let { if (it > 0) params.add("amountCents=$it") }
    payment.currency?.let { if (it.isNotBlank()) params.add("currency=${encode(it)}") }
    return "com.orderingintelligence.consumer://order-payment?${params.joinToString("&")}"
  }

  private fun buildReorderLink(order: WatchReorder): String {
    val itemsParam = order.items.joinToString(",") { item ->
      "${encode(item.itemId)}:${item.quantity}"
    }
    val params = mutableListOf(
      "storeId=${encode(order.storeId)}",
      "items=$itemsParam"
    )
    if (order.title.isNotBlank()) params.add("title=${encode(order.title)}")
    if (order.currency.isNotBlank()) params.add("currency=${encode(order.currency)}")
    return "com.orderingintelligence.consumer://reorder?${params.joinToString("&")}"
  }

  private fun buildFuelLink(storeId: String, fuel: WatchFuelOrder, currency: String): String {
    val params = mutableListOf(
      "storeId=${encode(storeId)}",
      "gradeId=${encode(fuel.fuelGradeId)}"
    )
    if (fuel.fuelGradeName.isNotBlank()) {
      params.add("gradeName=${encode(fuel.fuelGradeName)}")
    }
    if (fuel.unitPriceCents > 0) params.add("unitPriceCents=${fuel.unitPriceCents}")
    val flow = fuel.paymentFlow.ifBlank { "prepay" }
    params.add("paymentFlow=${encode(flow)}")
    if (fuel.requestedAmountCents > 0) params.add("requestedAmountCents=${fuel.requestedAmountCents}")
    if (fuel.requestedLiters > 0) params.add("requestedLiters=${fuel.requestedLiters}")
    if (fuel.preauthAmountCents > 0) params.add("preauthAmountCents=${fuel.preauthAmountCents}")
    if (currency.isNotBlank()) params.add("currency=${encode(currency)}")
    return "com.orderingintelligence.consumer://fuel-order?${params.joinToString("&")}"
  }

  private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
}
