import Foundation

struct CarPlayReorderItem: Decodable {
  let itemId: String
  let quantity: Int
}

struct CarPlayReorder: Decodable {
  let storeId: String
  let storeName: String
  let title: String
  let items: [CarPlayReorderItem]
  let fuel: CarPlayFuelOrder?
  let currency: String?
}

struct CarPlayReorderResponse: Decodable {
  let results: [CarPlayReorder]
}

struct CarPlaySessionInfo: Decodable {
  let storeId: String?
  let storeName: String?
  let businessType: String?
  let currency: String?
  let fuelDefaultPrepayCents: Int?
  let fuelPreauthCapCents: Int?
}

struct CarPlayFuelOrder: Decodable {
  let fuelGradeId: String
  let fuelGradeName: String?
  let unitPriceCents: Int?
  let requestedLiters: Double?
  let requestedAmountCents: Int?
  let preauthAmountCents: Int?
  let paymentFlow: String?
}

struct CarPlayMenuItem: Decodable {
  let id: String
  let name: String
  let priceCents: Int?
}

struct CarPlayMenuSnapshot: Decodable {
  let items: [CarPlayMenuItem]
}

struct CarPlayPaymentMethod: Decodable {
  let id: String
  let isDefault: Bool
}

struct CarPlayPaymentMethodsResponse: Decodable {
  let methods: [CarPlayPaymentMethod]
}

struct CarPlayOffSessionResult: Decodable {
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

struct CarPlayOrderPaymentResult {
  let orderId: String
  let payment: CarPlayOffSessionResult
}
