import CarPlay
import Foundation

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  let sessionStore = CarPlaySessionStore()
  lazy var client = CarPlayClient(sessionIdProvider: { [weak self] in
    self?.sessionStore.sessionId()
  })
  let fallbackFuelPrepayCents = 5000
  var hasDefaultPaymentMethod = false
  var currentSession: CarPlaySessionInfo?

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                didConnect interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    showLoadingTemplate()
    Task { await loadHome() }
  }

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                didDisconnect interfaceController: CPInterfaceController) {
    self.interfaceController = nil
    currentSession = nil
  }

  private func showLoadingTemplate() {
    let template = CPInformationTemplate(title: "Ordering", layout: .leading)
    template.setInformationItems([CPInformationItem(title: "Loading", detail: "Fetching recent orders...")])
    interfaceController?.setRootTemplate(template, animated: false)
  }

  private func loadHome() async {
    do {
      let session = try await client.fetchSession()
      currentSession = session
      let reorders = try await client.fetchRecentReorders(limit: 3)
      hasDefaultPaymentMethod = (try? await client.hasDefaultPaymentMethod()) ?? false

      var sections: [CPListSection] = []
      if let fuelSection = await buildFuelSection(session: session) {
        sections.append(fuelSection)
      }
      let reorderSection = buildReorderSection(reorders: reorders)
      sections.append(reorderSection)

      let template = CPListTemplate(title: "Quick Reorder", sections: sections)
      interfaceController?.setRootTemplate(template, animated: true)
    } catch {
      let template = CPInformationTemplate(title: "Ordering", layout: .leading)
      template.setInformationItems([CPInformationItem(title: "Error", detail: error.localizedDescription)])
      interfaceController?.setRootTemplate(template, animated: true)
    }
  }

  private func buildReorderSection(reorders: [CarPlayReorder]) -> CPListSection {
    let listItems = reorders.map { order in
      CPListItem(text: order.storeName.isEmpty ? "Recent order" : order.storeName,
                 detailText: order.title.isEmpty ? "Reorder" : order.title,
                 image: nil,
                 accessoryImage: nil)
    }
    listItems.enumerated().forEach { index, item in
      item.handler = { [weak self] _, completion in
        Task {
          await self?.confirmReorder(order: reorders[index])
          completion()
        }
      }
    }
    if listItems.isEmpty {
      let empty = CPListItem(text: "No recent orders", detailText: "Place an order in the mobile app.")
      return CPListSection(items: [empty])
    }
    return CPListSection(items: listItems)
  }

  private func confirmReorder(order: CarPlayReorder) async {
    if let fuel = order.fuel {
      await confirmFuelReorder(order: order, fuel: fuel)
      return
    }
    let confirm = CPAlertAction(title: "Confirm", style: .default) { [weak self] _ in
      Task {
        guard let self else { return }
        let canPay = await self.ensureDefaultPaymentMethod()
        if !canPay {
          let link = self.buildReorderHandoffLink(order: order)
          self.sessionStore.saveHandoffLink(link)
          self.presentHandoffAlert(message: "Open the mobile app to add a card.")
          return
        }
        await self.placeReorder(order: order)
      }
    }
    let cancel = CPAlertAction(title: "Cancel", style: .cancel, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: ["Reorder from \(order.storeName)"], actions: [confirm, cancel])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  private func placeReorder(order: CarPlayReorder) async {
    do {
      let result = try await client.placeReorder(order: order)
      if result.payment.succeeded {
        let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
        let alert = CPAlertTemplate(titleVariants: ["Order placed"], actions: [done])
        interfaceController?.presentTemplate(alert, animated: true)
        return
      }
      if result.payment.requiresAction,
         let link = buildOrderPaymentHandoffLink(
          orderId: result.orderId,
          payment: result.payment
         ) {
        sessionStore.saveHandoffLink(link)
        presentHandoffAlert(message: "Open the mobile app to complete payment.")
        return
      }
      let message = result.payment.error ?? "Payment failed"
      let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
      let alert = CPAlertTemplate(titleVariants: ["Failed", message], actions: [done])
      interfaceController?.presentTemplate(alert, animated: true)
    } catch {
      let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
      let alert = CPAlertTemplate(titleVariants: ["Failed", error.localizedDescription], actions: [done])
      interfaceController?.presentTemplate(alert, animated: true)
    }
  }

  func ensureDefaultPaymentMethod() async -> Bool {
    if hasDefaultPaymentMethod { return true }
    let available = (try? await client.hasDefaultPaymentMethod()) ?? false
    hasDefaultPaymentMethod = available
    return available
  }

  private func buildReorderHandoffLink(order: CarPlayReorder) -> String {
    let items = order.items.map { "\(encode($0.itemId)):\($0.quantity)" }.joined(separator: ",")
    var parts = [
      "storeId=\(encode(order.storeId))",
      "items=\(items)"
    ]
    if !order.title.isEmpty {
      parts.append("title=\(encode(order.title))")
    }
    if let currency = order.currency, !currency.isEmpty {
      parts.append("currency=\(encode(currency))")
    }
    return "com.orderingintelligence.consumer://reorder?\(parts.joined(separator: "&"))"
  }

  func buildOrderPaymentHandoffLink(
    orderId: String,
    payment: CarPlayOffSessionResult
  ) -> String? {
    guard let clientSecret = payment.clientSecret, !clientSecret.isEmpty else {
      return nil
    }
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

  func presentHandoffAlert(message: String) {
    let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: [message], actions: [done])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func encode(_ value: String) -> String {
    return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
  }
}
