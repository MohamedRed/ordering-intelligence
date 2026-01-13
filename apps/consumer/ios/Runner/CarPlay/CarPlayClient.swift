import Foundation

final class CarPlayClient {
  private let baseURL: URL
  private let sessionIdProvider: () -> String?

  init(
    baseURL: URL = URL(string: "https://channel-gateway-230152279015.us-central1.run.app")!,
    sessionIdProvider: @escaping () -> String? = { nil }
  ) {
    self.baseURL = baseURL
    self.sessionIdProvider = sessionIdProvider
  }

  func fetchRecentReorders(limit: Int) async throws -> [CarPlayReorder] {
    guard let sessionId = sessionIdProvider() else {
      throw NSError(domain: "carplay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing session"])
    }
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/reorders/recent"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "sessionId", value: sessionId),
      URLQueryItem(name: "limit", value: String(limit))
    ]
    guard let url = components?.url else { return [] }

    let (data, _) = try await URLSession.shared.data(from: url)
    let response = try JSONDecoder().decode(CarPlayReorderResponse.self, from: data)
    return response.results
  }

  func placeReorder(order: CarPlayReorder) async throws -> CarPlayOrderPaymentResult {
    guard let sessionId = sessionIdProvider() else {
      throw NSError(domain: "carplay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing session"])
    }
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
      throw NSError(domain: "carplay", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Order failed"])
    }
    let payloadJson = try JSONSerialization.jsonObject(with: data, options: [])
    let orderId = (payloadJson as? [String: Any])?["id"] as? String ?? ""
    if orderId.isEmpty {
      throw NSError(domain: "carplay", code: 422, userInfo: [NSLocalizedDescriptionKey: "Missing order id"])
    }
    let payment = try await payOrderWithDefault(orderId: orderId, sessionId: sessionId)
    return CarPlayOrderPaymentResult(orderId: orderId, payment: payment)
  }

  func fetchSession() async throws -> CarPlaySessionInfo {
    guard let sessionId = sessionIdProvider() else {
      throw NSError(domain: "carplay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing session"])
    }
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/session"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
    guard let url = components?.url else {
      throw NSError(domain: "carplay", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid session URL"])
    }
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(CarPlaySessionInfo.self, from: data)
  }

  func fetchMenu(storeId: String) async throws -> [CarPlayMenuItem] {
    let encoded = storeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storeId
    let url = baseURL.appendingPathComponent("/mobile/stores/\(encoded)/menu")
    let (data, _) = try await URLSession.shared.data(from: url)
    let response = try JSONDecoder().decode(CarPlayMenuSnapshot.self, from: data)
    return response.items
  }

  func hasDefaultPaymentMethod() async throws -> Bool {
    guard let sessionId = sessionIdProvider() else {
      throw NSError(domain: "carplay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing session"])
    }
    var components = URLComponents(url: baseURL.appendingPathComponent("/mobile/payment-methods"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
    guard let url = components?.url else { return false }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
      return false
    }
    let decoded = try JSONDecoder().decode(CarPlayPaymentMethodsResponse.self, from: data)
    return decoded.methods.contains(where: { $0.isDefault })
  }

  func placeFuelOrder(
    storeId: String,
    fuel: [String: Any],
    amountCents: Int,
    currency: String?
  ) async throws -> CarPlayOrderPaymentResult {
    guard let sessionId = sessionIdProvider() else {
      throw NSError(domain: "carplay", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing session"])
    }
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
      throw NSError(domain: "carplay", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Order failed"])
    }
    let payloadJson = try JSONSerialization.jsonObject(with: data, options: [])
    let orderId = (payloadJson as? [String: Any])?["id"] as? String ?? ""
    if orderId.isEmpty {
      throw NSError(domain: "carplay", code: 422, userInfo: [NSLocalizedDescriptionKey: "Missing order id"])
    }
    let payment = try await payOrderWithDefault(
      orderId: orderId,
      sessionId: sessionId,
      amountCents: amountCents,
      currency: currency
    )
    return CarPlayOrderPaymentResult(orderId: orderId, payment: payment)
  }

  private func payOrderWithDefault(
    orderId: String,
    sessionId: String,
    amountCents: Int? = nil,
    currency: String? = nil
  ) async throws -> CarPlayOffSessionResult {
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
      throw NSError(domain: "carplay", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Payment failed"])
    }
    return try JSONDecoder().decode(CarPlayOffSessionResult.self, from: data)
  }
}
