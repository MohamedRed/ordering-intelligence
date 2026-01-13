import Foundation

final class WatchAPIClient {
  private let baseURL = URL(string: "https://channel-gateway-230152279015.us-central1.run.app")!

  func fetchSession(sessionId: String) async throws -> WatchSessionInfo? {
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/session"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
    guard let url = components?.url else { return nil }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      return nil
    }
    return try JSONDecoder().decode(WatchSessionInfo.self, from: data)
  }

  func fetchRecentReorders(sessionId: String, limit: Int = 3) async throws -> [WatchReorder] {
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/reorders/recent"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "sessionId", value: sessionId),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components?.url else { return [] }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      return []
    }
    let payload = try JSONDecoder().decode(WatchReorderResponse.self, from: data)
    return payload.results
  }

  func hasDefaultPaymentMethod(sessionId: String) async throws -> Bool {
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/payment-methods"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
    guard let url = components?.url else { return false }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      return false
    }
    let payload = try JSONDecoder().decode(WatchPaymentMethodsResponse.self, from: data)
    return payload.methods.contains(where: { $0.isDefault })
  }

  func placeReorder(order: WatchReorder, sessionId: String) async throws -> WatchOrderPaymentResult {
    let url = baseURL.appendingPathComponent("/mobile/orders")
    let payload: [String: Any] = [
      "sessionId": sessionId,
      "storeId": order.storeId,
      "paymentMethod": "card",
      "items": order.items.map { ["itemId": $0.itemId, "quantity": $0.quantity] }
    ]
    let body = try JSONSerialization.data(withJSONObject: payload, options: [])
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      throw NSError(domain: "watch", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Order failed"])
    }
    let payloadJson = try JSONSerialization.jsonObject(with: data, options: [])
    let orderId = (payloadJson as? [String: Any])?["id"] as? String ?? ""
    if orderId.isEmpty {
      throw NSError(domain: "watch", code: 422, userInfo: [NSLocalizedDescriptionKey: "Missing order id"])
    }
    let payment = try await payOrderWithDefault(orderId: orderId, sessionId: sessionId)
    return WatchOrderPaymentResult(orderId: orderId, payment: payment)
  }

  func placeFuelOrder(
    sessionId: String,
    storeId: String,
    fuel: [String: Any],
    amountCents: Int,
    currency: String?
  ) async throws -> WatchOrderPaymentResult {
    let url = baseURL.appendingPathComponent("/mobile/orders")
    let payload: [String: Any] = [
      "sessionId": sessionId,
      "storeId": storeId,
      "paymentMethod": "card",
      "items": [],
      "fuel": fuel
    ]
    let body = try JSONSerialization.data(withJSONObject: payload, options: [])
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      throw NSError(domain: "watch", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Order failed"])
    }
    let payloadJson = try JSONSerialization.jsonObject(with: data, options: [])
    let orderId = (payloadJson as? [String: Any])?["id"] as? String ?? ""
    if orderId.isEmpty {
      throw NSError(domain: "watch", code: 422, userInfo: [NSLocalizedDescriptionKey: "Missing order id"])
    }
    let payment = try await payOrderWithDefault(
      orderId: orderId,
      sessionId: sessionId,
      amountCents: amountCents,
      currency: currency
    )
    return WatchOrderPaymentResult(orderId: orderId, payment: payment)
  }

  private func payOrderWithDefault(
    orderId: String,
    sessionId: String,
    amountCents: Int? = nil,
    currency: String? = nil
  ) async throws -> WatchOffSessionResult {
    let url = baseURL.appendingPathComponent("/mobile/orders/\(orderId)/pay-default")
    var payload: [String: Any] = ["sessionId": sessionId]
    if let amountCents = amountCents, amountCents > 0 {
      payload["amountCents"] = amountCents
    }
    if let currency = currency, !currency.isEmpty {
      payload["currency"] = currency
    }
    let body = try JSONSerialization.data(withJSONObject: payload, options: [])
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      throw NSError(domain: "watch", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Payment failed"])
    }
    return try JSONDecoder().decode(WatchOffSessionResult.self, from: data)
  }
}
