package com.orderingintelligence.auto

data class AutoReorderItem(val itemId: String, val quantity: Int)

data class AutoFuelOrder(
  val fuelGradeId: String,
  val fuelGradeName: String,
  val unitPriceCents: Int,
  val requestedLiters: Double,
  val requestedAmountCents: Int,
  val preauthAmountCents: Int,
  val paymentFlow: String
)

data class AutoReorder(
  val storeId: String,
  val storeName: String,
  val title: String,
  val items: List<AutoReorderItem>,
  val fuel: AutoFuelOrder? = null,
  val currency: String = ""
)

data class AutoSessionInfo(
  val storeId: String,
  val storeName: String,
  val businessType: String,
  val currency: String,
  val fuelDefaultPrepayCents: Int,
  val fuelPreauthCapCents: Int
)

data class AutoMenuItem(
  val id: String,
  val name: String,
  val priceCents: Int
)

data class AutoPaymentMethod(
  val id: String,
  val isDefault: Boolean
)

data class AutoOffSessionResult(
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

data class AutoOrderPaymentResult(
  val orderId: String,
  val payment: AutoOffSessionResult
)
