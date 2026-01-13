import Foundation

enum WatchHandoffLink {
  static func buildLink(for order: WatchReorder) -> String {
    if let fuel = order.fuel {
      return buildFuelLink(storeId: order.storeId, fuel: fuel, currency: order.currency ?? "")
    }
    return buildReorderLink(order: order)
  }

  static func buildOrderPaymentLink(orderId: String, payment: WatchOffSessionResult) -> String? {
    guard let clientSecret = payment.clientSecret, !clientSecret.isEmpty else { return nil }
    var parts = [
      "orderId=\(encode(orderId))",
      "clientSecret=\(encode(clientSecret))"
    ]
    if let paymentId = payment.paymentId, !paymentId.isEmpty {
      parts.append("paymentId=\(encode(paymentId))")
    }
    if let intentId = payment.paymentIntentId, !intentId.isEmpty {
      parts.append("paymentIntentId=\(encode(intentId))")
    }
    if let customerId = payment.customerId, !customerId.isEmpty {
      parts.append("customerId=\(encode(customerId))")
    }
    if let ephemeralKey = payment.ephemeralKey, !ephemeralKey.isEmpty {
      parts.append("ephemeralKey=\(encode(ephemeralKey))")
    }
    if let accountId = payment.stripeAccountId, !accountId.isEmpty {
      parts.append("stripeAccountId=\(encode(accountId))")
    }
    if let publishableKey = payment.publishableKey, !publishableKey.isEmpty {
      parts.append("publishableKey=\(encode(publishableKey))")
    }
    if let amount = payment.amountCents, amount > 0 {
      parts.append("amountCents=\(amount)")
    }
    if let currency = payment.currency, !currency.isEmpty {
      parts.append("currency=\(encode(currency))")
    }
    return "com.orderingintelligence.consumer://order-payment?\(parts.joined(separator: "&"))"
  }

  private static func buildReorderLink(order: WatchReorder) -> String {
    let items = order.items.map { "\(encode($0.itemId)):\($0.quantity)" }.joined(separator: ",")
    var parts = [
      "storeId=\(encode(order.storeId))",
      "items=\(items)",
    ]
    if !order.title.isEmpty {
      parts.append("title=\(encode(order.title))")
    }
    if let currency = order.currency, !currency.isEmpty {
      parts.append("currency=\(encode(currency))")
    }
    return "com.orderingintelligence.consumer://reorder?\(parts.joined(separator: "&"))"
  }

  private static func buildFuelLink(storeId: String, fuel: WatchFuelOrder, currency: String) -> String {
    var parts: [String] = [
      "storeId=\(encode(storeId))",
      "gradeId=\(encode(fuel.fuelGradeId))",
    ]
    if let name = fuel.fuelGradeName, !name.isEmpty {
      parts.append("gradeName=\(encode(name))")
    }
    if let price = fuel.unitPriceCents, price > 0 {
      parts.append("unitPriceCents=\(price)")
    }
    let flow = fuel.paymentFlow ?? "prepay"
    parts.append("paymentFlow=\(encode(flow))")
    if let amount = fuel.requestedAmountCents, amount > 0 {
      parts.append("requestedAmountCents=\(amount)")
    }
    if let liters = fuel.requestedLiters, liters > 0 {
      parts.append("requestedLiters=\(liters)")
    }
    if let preauth = fuel.preauthAmountCents, preauth > 0 {
      parts.append("preauthAmountCents=\(preauth)")
    }
    if !currency.isEmpty {
      parts.append("currency=\(encode(currency))")
    }
    return "com.orderingintelligence.consumer://fuel-order?\(parts.joined(separator: "&"))"
  }

  private static func encode(_ value: String) -> String {
    return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
  }
}
