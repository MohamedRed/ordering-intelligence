package com.orderingintelligence.auto

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import java.util.concurrent.Executors

class ReorderScreen(carContext: CarContext) : Screen(carContext) {
  private val sessionStore = AutoSessionStore(carContext)
  private val client = AutoClient(sessionIdProvider = { sessionStore.sessionId() })
  private val executor = Executors.newSingleThreadExecutor()
  private var state: ReorderScreenState = ReorderScreenState.Loading
  private val fallbackFuelPrepayCents = 5000

  init {
    loadOrders()
  }

  private fun loadOrders() {
    executor.execute {
      state = try {
        val session = client.fetchSession()
        val orders = client.fetchRecentReorders(limit = 3)
        val fuelGrades = if (session != null &&
          session.businessType.trim().lowercase() == "gas_station" &&
          session.storeId.isNotBlank()
        ) {
          client.fetchMenu(session.storeId)
        } else {
          emptyList()
        }
        val hasDefaultPaymentMethod = client.hasDefaultPaymentMethod()
        ReorderScreenState.Loaded(
          orders = orders,
          fuelGrades = fuelGrades,
          session = session,
          hasDefaultPaymentMethod = hasDefaultPaymentMethod
        )
      } catch (err: Exception) {
        ReorderScreenState.Error(err.message ?: "Failed to load orders")
      }
      invalidate()
    }
  }

  override fun onGetTemplate(): Template {
    val listBuilder = ItemList.Builder()
    when (val current = state) {
      ReorderScreenState.Loading -> {
        listBuilder.addItem(
          Row.Builder()
            .setTitle("Loading recent orders")
            .addText("Please wait...")
            .build()
        )
      }
      is ReorderScreenState.Error -> {
        listBuilder.addItem(
          Row.Builder()
            .setTitle("Unable to load orders")
            .addText(current.message)
            .build()
        )
      }
      is ReorderScreenState.Loaded -> {
        val currency = current.session?.currency?.ifBlank { "EUR" }?.uppercase() ?: "EUR"
        val fuelPreauthCap = resolveFuelPreauthCap(current.session, fallbackFuelPrepayCents)
        val storeId = current.session?.storeId?.trim().orEmpty()
        if (current.fuelGrades.isNotEmpty() && storeId.isNotEmpty()) {
          current.fuelGrades.forEach { grade ->
            val title = if (grade.name.isBlank()) "Fuel order" else "Fuel: ${grade.name}"
            val priceLabel = if (grade.priceCents > 0) {
              "Authorize $currency ${formatCents(fuelPreauthCap)} • $currency ${formatCents(grade.priceCents)}/L"
            } else {
              "Authorize $currency ${formatCents(fuelPreauthCap)}"
            }
            val row = Row.Builder()
              .setTitle(title)
              .addText(priceLabel)
              .setOnClickListener {
                executor.execute {
                  try {
                    handleFuelGradeClick(
                      carContext = carContext,
                      sessionStore = sessionStore,
                      client = client,
                      session = current.session,
                      grade = grade,
                      hasDefaultPaymentMethod = current.hasDefaultPaymentMethod,
                      fallbackFuelPreauthCents = fallbackFuelPreauthCents
                    )
                  } catch (err: Exception) {
                    CarToast.makeText(
                      carContext,
                      err.message ?: "Fuel order failed",
                      CarToast.LENGTH_SHORT
                    ).show()
                  }
                }
              }
              .build()
            listBuilder.addItem(row)
          }
        }
        if (current.orders.isEmpty()) {
          listBuilder.addItem(
            Row.Builder()
              .setTitle("No recent orders")
              .addText("Place an order in the mobile app first.")
              .build()
          )
        } else {
          current.orders.forEach { order ->
            val row = Row.Builder()
              .setTitle(if (order.storeName.isBlank()) "Recent order" else order.storeName)
              .addText(if (order.title.isBlank()) "Reorder" else order.title)
              .setOnClickListener {
                executor.execute {
                  try {
                    if (order.fuel != null) {
                      handleFuelReorderClick(
                        carContext = carContext,
                        sessionStore = sessionStore,
                        client = client,
                        order = order,
                        session = current.session,
                        hasDefaultPaymentMethod = current.hasDefaultPaymentMethod,
                        fallbackFuelPreauthCents = fallbackFuelPreauthCents
                      )
                    } else {
                      handleReorderClick(
                        carContext = carContext,
                        sessionStore = sessionStore,
                        client = client,
                        order = order,
                        hasDefaultPaymentMethod = current.hasDefaultPaymentMethod
                      )
                    }
                  } catch (err: Exception) {
                    CarToast.makeText(
                      carContext,
                      err.message ?: "Order failed",
                      CarToast.LENGTH_SHORT
                    ).show()
                  }
                }
              }
              .build()
            listBuilder.addItem(row)
          }
        }
      }
    }

    return ListTemplate.Builder()
      .setTitle("Quick Reorder")
      .setSingleList(listBuilder.build())
      .setHeaderAction(Action.APP_ICON)
      .build()
  }
}
