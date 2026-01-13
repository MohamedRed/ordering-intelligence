import Foundation

struct WatchReorderItem: Decodable {
  let itemId: String
  let quantity: Int
}

struct WatchSessionInfo: Decodable {
  let storeId: String?
  let storeName: String?
  let businessType: String?
  let currency: String?
  let fuelDefaultPrepayCents: Int?
  let fuelPreauthCapCents: Int?
}

struct WatchFuelOrder: Decodable {
  let fuelGradeId: String
  let fuelGradeName: String?
  let unitPriceCents: Int?
  let requestedLiters: Double?
  let requestedAmountCents: Int?
  let preauthAmountCents: Int?
  let paymentFlow: String?
}

struct WatchReorder: Decodable, Identifiable {
  let storeId: String
  let storeName: String
  let title: String
  let items: [WatchReorderItem]
  let fuel: WatchFuelOrder?
  let currency: String?

  var id: String { "\(storeId)_\(title)" }
}

struct WatchReorderResponse: Decodable {
  let results: [WatchReorder]
}

struct WatchPaymentMethod: Decodable {
  let id: String
  let isDefault: Bool
}

struct WatchPaymentMethodsResponse: Decodable {
  let methods: [WatchPaymentMethod]
}

struct WatchOffSessionResult: Decodable {
  let status: String
  let paymentId: String?
  let paymentIntentId: String?
  let clientSecret: String?
  let customerId: String?
  let ephemeralKey: String?
  let stripeAccountId: String?
  let publishableKey: String?
  let amountCents: Int?
  let currency: String?
  let error: String?

  var requiresAction: Bool { status == "requires_action" }
  var succeeded: Bool {
    return status == "succeeded" || status == "requires_capture" || status == "processing"
  }
}

struct WatchOrderPaymentResult {
  let orderId: String
  let payment: WatchOffSessionResult
}
