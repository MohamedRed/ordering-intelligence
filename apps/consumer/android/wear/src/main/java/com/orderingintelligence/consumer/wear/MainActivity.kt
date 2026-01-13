package com.orderingintelligence.consumer.wear

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.wear.activity.WearableActivity
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.tasks.Tasks
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

class MainActivity : WearableActivity() {
  private val executor = Executors.newSingleThreadExecutor()
  private lateinit var statusText: TextView
  private lateinit var refreshButton: Button
  private lateinit var ordersContainer: LinearLayout
  private val apiClient = WatchApiClient()
  private var sessionId: String? = null
  private var sessionInfo: WatchSessionInfo? = null
  private val fallbackFuelPreauthCents = 5000

  private val messageListener = MessageClient.OnMessageReceivedListener { event ->
    if (event.path == "/session/response") {
      sessionId = event.data?.toString(StandardCharsets.UTF_8)
      fetchOrders()
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)
    setAmbientEnabled()
    statusText = findViewById(R.id.status_text)
    refreshButton = findViewById(R.id.refresh_button)
    ordersContainer = findViewById(R.id.orders_container)
    refreshButton.setOnClickListener { refresh() }
    refresh()
  }

  override fun onStart() {
    super.onStart()
    Wearable.getMessageClient(this).addListener(messageListener)
  }

  override fun onStop() {
    Wearable.getMessageClient(this).removeListener(messageListener)
    super.onStop()
  }

  private fun refresh() {
    if (sessionId.isNullOrBlank()) {
      requestSessionId()
    } else {
      fetchOrders()
    }
  }

  private fun requestSessionId() {
    updateStatus("Waiting for phone…")
    executor.execute {
      val nodes = try {
        Tasks.await(Wearable.getNodeClient(this).connectedNodes)
      } catch (_: Exception) {
        emptyList()
      }
      if (nodes.isEmpty()) {
        runOnUiThread { updateStatus("Open the mobile app to connect.") }
        return@execute
      }
      val nodeId = nodes.first().id
      Wearable.getMessageClient(this)
        .sendMessage(nodeId, "/session/request", ByteArray(0))
    }
  }

  private fun fetchOrders() {
    val currentSession = sessionId?.trim().orEmpty()
    if (currentSession.isEmpty()) {
      updateStatus("Open the mobile app to connect.")
      return
    }
    updateStatus("Loading orders…")
    executor.execute {
      try {
        sessionInfo = apiClient.fetchSession(currentSession)
        val orders = apiClient.fetchRecentReorders(currentSession)
        runOnUiThread { renderOrders(orders) }
      } catch (err: Exception) {
        runOnUiThread { updateStatus(err.message ?: "Failed to load orders") }
      }
    }
  }

  private fun renderOrders(orders: List<WatchReorder>) {
    ordersContainer.removeAllViews()
    if (orders.isEmpty()) {
      updateStatus("No recent orders")
      return
    }
    updateStatus("Tap to reorder")
    for (order in orders) {
      val button = Button(this)
      val label = if (order.title.isNotBlank()) order.title else {
        if (order.fuel != null) "Fuel reorder" else "Reorder"
      }
      button.text = label
      button.setOnClickListener { handleOrderTap(order) }
      ordersContainer.addView(button)
    }
  }

  private fun handleOrderTap(order: WatchReorder) {
    val currentSession = sessionId?.trim().orEmpty()
    if (currentSession.isEmpty()) {
      updateStatus("Open the mobile app to connect.")
      return
    }
    if (order.fuel != null) {
      val fuel = order.fuel ?: return
      updateStatus("Placing fuel order…")
      executor.execute {
        try {
          val hasDefault = apiClient.hasDefaultPaymentMethod(currentSession)
          if (!hasDefault) {
            sendLinkToPhone(WatchHandoffLink.buildLink(order), "Open phone to add a card")
            return@execute
          }
          val cap = resolveFuelPreauthCap(sessionInfo, fallbackFuelPreauthCents)
          val plan = resolveFuelPaymentPlan(fuel, cap)
          if (plan == null) {
            sendLinkToPhone(WatchHandoffLink.buildLink(order), "Open phone to finish payment")
            return@execute
          }
          val currency = if (order.currency.isNotBlank()) order.currency else sessionInfo?.currency.orEmpty()
          val result = apiClient.placeFuelOrder(
            sessionId = currentSession,
            storeId = order.storeId,
            fuel = buildFuelPayload(fuel, plan),
            amountCents = plan.amountCents,
            currency = currency
          )
          when {
            result.payment.succeeded -> runOnUiThread { updateStatus("Fuel order placed") }
            result.payment.requiresAction -> {
              val link = WatchHandoffLink.buildOrderPaymentLink(result.orderId, result.payment)
              if (link != null) {
                sendLinkToPhone(link, "Open phone to complete payment")
              } else {
                runOnUiThread { updateStatus("Payment needs phone approval") }
              }
            }
            else -> runOnUiThread {
              updateStatus(result.payment.error ?: "Payment failed")
            }
          }
        } catch (err: Exception) {
          runOnUiThread { updateStatus(err.message ?: "Order failed") }
        }
      }
      return
    }
    updateStatus("Placing order…")
    executor.execute {
      try {
        val hasDefault = apiClient.hasDefaultPaymentMethod(currentSession)
        if (!hasDefault) {
          sendLinkToPhone(WatchHandoffLink.buildLink(order), "Open phone to add a card")
          return@execute
        }
        val result = apiClient.placeReorder(currentSession, order)
        when {
          result.payment.succeeded -> runOnUiThread { updateStatus("Order placed") }
          result.payment.requiresAction -> {
            val link = WatchHandoffLink.buildOrderPaymentLink(result.orderId, result.payment)
            if (link != null) {
              sendLinkToPhone(link, "Open phone to complete payment")
            } else {
              runOnUiThread { updateStatus("Payment needs phone approval") }
            }
          }
          else -> runOnUiThread {
            updateStatus(result.payment.error ?: "Payment failed")
          }
        }
      } catch (err: Exception) {
        runOnUiThread { updateStatus(err.message ?: "Order failed") }
      }
    }
  }

  private fun sendLinkToPhone(link: String, statusMessage: String) {
    executor.execute {
      val nodes = try {
        Tasks.await(Wearable.getNodeClient(this).connectedNodes)
      } catch (_: Exception) {
        emptyList()
      }
      if (nodes.isEmpty()) {
        runOnUiThread { updateStatus("Phone not connected.") }
        return@execute
      }
      val nodeId = nodes.first().id
      Wearable.getMessageClient(this)
        .sendMessage(
          nodeId,
          "/handoff",
          link.toByteArray(StandardCharsets.UTF_8),
        )
      runOnUiThread { updateStatus(statusMessage) }
    }
  }

  private fun updateStatus(message: String) {
    statusText.text = message
    statusText.visibility = View.VISIBLE
  }
}
