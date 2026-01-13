package com.orderingintelligence.consumer.wear

data class WatchReorderItem(val itemId: String, val quantity: Int)

data class WatchSessionInfo(
  val storeId: String,
  val storeName: String,
  val businessType: String,
  val currency: String,
  val fuelDefaultPrepayCents: Int,
  val fuelPreauthCapCents: Int
)

data class WatchFuelOrder(
  val fuelGradeId: String,
  val fuelGradeName: String,
  val unitPriceCents: Int,
  val requestedLiters: Double,
  val requestedAmountCents: Int,
  val preauthAmountCents: Int,
  val paymentFlow: String
)

data class WatchReorder(
  val storeId: String,
  val storeName: String,
  val title: String,
  val items: List<WatchReorderItem>,
  val currency: String,
  val fuel: WatchFuelOrder? = null
)

data class WatchPaymentMethod(
  val id: String,
  val isDefault: Boolean
)

data class WatchOffSessionResult(
  val status: String,
  val paymentId: String?,
  val paymentIntentId: String?,
  val clientSecret: String?,
  val customerId: String?,
  val ephemeralKey: String?,
  val stripeAccountId: String?,
  val publishableKey: String?,
  val amountCents: Int?,
  val currency: String?,
  val error: String?
) {
  val requiresAction: Boolean
    get() = status == "requires_action"
  val succeeded: Boolean
    get() = status == "succeeded" || status == "requires_capture" || status == "processing"
}

data class WatchOrderPaymentResult(
  val orderId: String,
  val payment: WatchOffSessionResult
)
