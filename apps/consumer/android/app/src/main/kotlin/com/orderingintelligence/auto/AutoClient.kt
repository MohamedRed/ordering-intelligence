package com.orderingintelligence.auto

import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

class AutoClient(
  private val baseUrl: String = "https://channel-gateway-230152279015.us-central1.run.app",
  private val sessionIdProvider: () -> String?
) {
  fun fetchSession(): AutoSessionInfo? {
    val sessionId = sessionIdProvider() ?: return null
    val url = URL("$baseUrl/mobile/session?sessionId=$sessionId")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "GET"
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    return try {
      if (connection.responseCode !in 200..299) return null
      val body = connection.inputStream.bufferedReader().readText()
      val json = JSONObject(body)
      AutoSessionInfo(
        storeId = json.optString("storeId"),
        storeName = json.optString("storeName"),
        businessType = json.optString("businessType"),
        currency = json.optString("currency"),
        fuelDefaultPrepayCents = json.optInt("fuelDefaultPrepayCents", 0),
        fuelPreauthCapCents = json.optInt("fuelPreauthCapCents", 0)
      )
    } finally {
      connection.disconnect()
    }
  }

  fun fetchRecentReorders(limit: Int): List<AutoReorder> {
    val sessionId = sessionIdProvider() ?: return emptyList()
    val url = URL("$baseUrl/mobile/reorders/recent?sessionId=$sessionId&limit=$limit")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "GET"
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    return try {
      if (connection.responseCode !in 200..299) return emptyList()
      val body = connection.inputStream.bufferedReader().readText()
      val json = JSONObject(body)
      val results = json.optJSONArray("results") ?: JSONArray()
      (0 until results.length()).mapNotNull { index ->
        val entry = results.optJSONObject(index) ?: return@mapNotNull null
        val itemsJson = entry.optJSONArray("items") ?: JSONArray()
        val items = (0 until itemsJson.length()).mapNotNull { itemIndex ->
          val item = itemsJson.optJSONObject(itemIndex) ?: return@mapNotNull null
          AutoReorderItem(
            itemId = item.optString("itemId"),
            quantity = item.optInt("quantity", 1)
          )
        }
        val fuelJson = entry.optJSONObject("fuel")
        val fuel = if (fuelJson != null) {
          AutoFuelOrder(
            fuelGradeId = fuelJson.optString("fuelGradeId"),
            fuelGradeName = fuelJson.optString("fuelGradeName"),
            unitPriceCents = fuelJson.optInt("unitPriceCents", 0),
            requestedLiters = fuelJson.optDouble("requestedLiters", 0.0),
            requestedAmountCents = fuelJson.optInt("requestedAmountCents", 0),
            preauthAmountCents = fuelJson.optInt("preauthAmountCents", 0),
            paymentFlow = fuelJson.optString("paymentFlow")
          )
        } else {
          null
        }
        AutoReorder(
          storeId = entry.optString("storeId"),
          storeName = entry.optString("storeName"),
          title = entry.optString("title"),
          items = items,
          fuel = fuel,
          currency = entry.optString("currency")
        )
      }
    } finally {
      connection.disconnect()
    }
  }

  fun placeReorder(order: AutoReorder): AutoOrderPaymentResult {
    val sessionId = sessionIdProvider() ?: throw IllegalStateException("Missing session")
    val url = URL("$baseUrl/mobile/orders")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.setRequestProperty("Content-Type", "application/json")
    connection.doOutput = true
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    val itemsJson = order.items.joinToString(prefix = "[", postfix = "]") { item ->
      "{\"itemId\":\"${item.itemId}\",\"quantity\":${item.quantity}}"
    }
    val payload = """
      {"sessionId":"$sessionId","storeId":"${order.storeId}","paymentMethod":"card","items":$itemsJson}
    """.trimIndent()
    connection.outputStream.use { it.write(payload.toByteArray()) }
    if (connection.responseCode !in 200..299) {
      connection.disconnect()
      throw IllegalStateException("Order failed")
    }
    val responseBody = connection.inputStream.bufferedReader().readText()
    connection.disconnect()
    val orderJson = JSONObject(responseBody)
    val orderId = orderJson.optString("id")
    if (orderId.isBlank()) {
      throw IllegalStateException("Missing order id")
    }
    val payment = payOrderWithDefault(orderId, sessionId)
    return AutoOrderPaymentResult(orderId = orderId, payment = payment)
  }

  fun placeFuelOrder(
    storeId: String,
    fuel: JSONObject,
    amountCents: Int,
    currency: String
  ): AutoOrderPaymentResult {
    val sessionId = sessionIdProvider() ?: throw IllegalStateException("Missing session")
    val url = URL("$baseUrl/mobile/orders")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.setRequestProperty("Content-Type", "application/json")
    connection.doOutput = true
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    val payload = JSONObject()
      .put("sessionId", sessionId)
      .put("storeId", storeId)
      .put("paymentMethod", "card")
      .put("items", JSONArray())
      .put("fuel", fuel)
    connection.outputStream.use { it.write(payload.toString().toByteArray()) }
    if (connection.responseCode !in 200..299) {
      connection.disconnect()
      throw IllegalStateException("Order failed")
    }
    val responseBody = connection.inputStream.bufferedReader().readText()
    connection.disconnect()
    val orderJson = JSONObject(responseBody)
    val orderId = orderJson.optString("id")
    if (orderId.isBlank()) {
      throw IllegalStateException("Missing order id")
    }
    val payment = payOrderWithDefault(orderId, sessionId, amountCents = amountCents, currency = currency)
    return AutoOrderPaymentResult(orderId = orderId, payment = payment)
  }

  fun fetchMenu(storeId: String): List<AutoMenuItem> {
    if (storeId.isBlank()) return emptyList()
    val url = URL("$baseUrl/mobile/stores/${storeId}/menu")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "GET"
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    return try {
      if (connection.responseCode !in 200..299) return emptyList()
      val body = connection.inputStream.bufferedReader().readText()
      val json = JSONObject(body)
      val items = json.optJSONArray("items") ?: JSONArray()
      (0 until items.length()).mapNotNull { index ->
        val item = items.optJSONObject(index) ?: return@mapNotNull null
        AutoMenuItem(
          id = item.optString("id"),
          name = item.optString("name"),
          priceCents = item.optInt("priceCents", 0)
        )
      }
    } finally {
      connection.disconnect()
    }
  }

  fun hasDefaultPaymentMethod(): Boolean {
    val sessionId = sessionIdProvider() ?: return false
    val url = URL("$baseUrl/mobile/payment-methods?sessionId=$sessionId")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "GET"
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    return try {
      if (connection.responseCode !in 200..299) return false
      val body = connection.inputStream.bufferedReader().readText()
      val json = JSONObject(body)
      val methods = json.optJSONArray("methods") ?: JSONArray()
      (0 until methods.length()).any { index ->
        val method = methods.optJSONObject(index) ?: return@any false
        method.optBoolean("isDefault", false)
      }
    } finally {
      connection.disconnect()
    }
  }

  private fun payOrderWithDefault(
    orderId: String,
    sessionId: String,
    amountCents: Int? = null,
    currency: String? = null
  ): AutoOffSessionResult {
    val url = URL("$baseUrl/mobile/orders/$orderId/pay-default")
    val connection = url.openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.setRequestProperty("Content-Type", "application/json")
    connection.doOutput = true
    connection.connectTimeout = 8000
    connection.readTimeout = 8000
    val payload = JSONObject().put("sessionId", sessionId)
    if (amountCents != null && amountCents > 0) {
      payload.put("amountCents", amountCents)
    }
    if (!currency.isNullOrBlank()) {
      payload.put("currency", currency)
    }
    connection.outputStream.use { it.write(payload.toString().toByteArray()) }
    if (connection.responseCode !in 200..299) {
      connection.disconnect()
      throw IllegalStateException("Payment failed")
    }
    val body = connection.inputStream.bufferedReader().readText()
    connection.disconnect()
    val json = JSONObject(body)
    return AutoOffSessionResult(
      status = json.optString("status"),
      paymentId = json.optString("paymentId").ifBlank { null },
      paymentIntentId = json.optString("paymentIntentId").ifBlank { null },
      clientSecret = json.optString("clientSecret").ifBlank { null },
      customerId = json.optString("customerId").ifBlank { null },
      ephemeralKey = json.optString("ephemeralKey").ifBlank { null },
      stripeAccountId = json.optString("stripeAccountId").ifBlank { null },
      publishableKey = json.optString("publishableKey").ifBlank { null },
      amountCents = if (json.has("amountCents")) json.optInt("amountCents") else null,
      currency = json.optString("currency").ifBlank { null },
      error = json.optString("error").ifBlank { null }
    )
  }
}
