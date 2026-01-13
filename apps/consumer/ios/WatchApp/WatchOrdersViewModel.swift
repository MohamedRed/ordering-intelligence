import Foundation

@MainActor
final class WatchOrdersViewModel: ObservableObject {
  @Published private(set) var orders: [WatchReorder] = []
  @Published private(set) var status: String? = nil
  @Published private(set) var isLoading = false

  private let sessionStore = WatchSessionStore()
  private let apiClient = WatchAPIClient()
  private let connectivity = WatchConnectivityManager.shared
  private var sessionInfo: WatchSessionInfo? = nil
  private let fallbackFuelPreauthCents = 5000

  func refresh() {
    guard let sessionId = sessionStore.sessionId(), !sessionId.isEmpty else {
      status = "Open the mobile app to connect."
      orders = []
      return
    }
    isLoading = true
    status = "Loading orders..."
    Task {
      do {
        sessionInfo = try? await apiClient.fetchSession(sessionId: sessionId)
        let results = try await apiClient.fetchRecentReorders(sessionId: sessionId)
        orders = results
        status = results.isEmpty ? "No recent orders" : "Tap to reorder"
      } catch {
        status = "Failed to load orders"
        orders = []
      }
      isLoading = false
    }
  }

  func handleOrderTap(_ order: WatchReorder) {
    guard let sessionId = sessionStore.sessionId(), !sessionId.isEmpty else {
      status = "Open the mobile app to connect."
      return
    }
    if let fuel = order.fuel {
      isLoading = true
      status = "Placing fuel order..."
      Task {
        defer { isLoading = false }
        do {
          let hasDefault = try await apiClient.hasDefaultPaymentMethod(sessionId: sessionId)
          if !hasDefault {
            sendHandoffLink(WatchHandoffLink.buildLink(for: order), message: "Open phone to add a card")
            return
          }
          let cap = resolveFuelPreauthCap(session: sessionInfo, fallbackCents: fallbackFuelPreauthCents)
          guard let plan = resolveFuelPaymentPlan(fuel: fuel, preauthCapCents: cap) else {
            sendHandoffLink(WatchHandoffLink.buildLink(for: order), message: "Open phone to finish payment")
            return
          }
          let currency = order.currency ?? sessionInfo?.currency ?? ""
          let result = try await apiClient.placeFuelOrder(
            sessionId: sessionId,
            storeId: order.storeId,
            fuel: buildFuelPayload(fuel: fuel, plan: plan),
            amountCents: plan.amountCents,
            currency: currency
          )
          if result.payment.succeeded {
            status = "Fuel order placed"
          } else if result.payment.requiresAction {
            if let link = WatchHandoffLink.buildOrderPaymentLink(orderId: result.orderId, payment: result.payment) {
              sendHandoffLink(link, message: "Open phone to complete payment")
            } else {
              status = "Payment needs phone approval"
            }
          } else {
            status = result.payment.error ?? "Payment failed"
          }
        } catch {
          status = "Order failed"
        }
      }
      return
    }
    isLoading = true
    status = "Placing order..."
    Task {
      do {
        let hasDefault = try await apiClient.hasDefaultPaymentMethod(sessionId: sessionId)
        if !hasDefault {
          sendHandoffLink(WatchHandoffLink.buildLink(for: order), message: "Open phone to add a card")
          isLoading = false
          return
        }
        let result = try await apiClient.placeReorder(order: order, sessionId: sessionId)
        if result.payment.succeeded {
          status = "Order placed"
        } else if result.payment.requiresAction,
          let link = WatchHandoffLink.buildOrderPaymentLink(orderId: result.orderId, payment: result.payment) {
          sendHandoffLink(link, message: "Open phone to complete payment")
        } else {
          status = result.payment.error ?? "Payment failed"
        }
      } catch {
        status = "Order failed"
      }
      isLoading = false
    }
  }

  private func sendHandoffLink(_ link: String, message: String) {
    connectivity.sendHandoffLink(link)
    status = message
  }
}
