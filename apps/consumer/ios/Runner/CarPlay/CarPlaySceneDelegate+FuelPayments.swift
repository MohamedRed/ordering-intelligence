import CarPlay
import Foundation

extension CarPlaySceneDelegate {
  func placeFuelOrder(
    storeId: String,
    grade: CarPlayMenuItem,
    amountCents: Int,
    currency: String
  ) async {
    do {
      let fuelPayload: [String: Any] = [
        "fuelGradeId": grade.id,
        "fuelGradeName": grade.name,
        "unit": "liter",
        "unitPriceCents": grade.priceCents ?? 0,
        "preauthAmountCents": amountCents,
        "paymentFlow": "preauth"
      ]
      let result = try await client.placeFuelOrder(
        storeId: storeId,
        fuel: fuelPayload,
        amountCents: amountCents,
        currency: currency
      )
      await handleFuelPaymentResult(result)
    } catch {
      let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
      let alert = CPAlertTemplate(titleVariants: ["Failed", error.localizedDescription], actions: [done])
      interfaceController?.presentTemplate(alert, animated: true)
    }
  }

  func placeFuelReorder(order: CarPlayReorder, fuel: CarPlayFuelOrder) async {
    let cap = effectiveFuelPreauthCap(session: currentSession)
    var paymentFlow = (fuel.paymentFlow ?? "prepay").lowercased()
    var requestedAmount = fuel.requestedAmountCents ?? 0
    let requestedLiters = fuel.requestedLiters ?? 0
    let unitPrice = fuel.unitPriceCents ?? 0
    var preauthAmount = fuel.preauthAmountCents ?? 0

    if paymentFlow == "preauth" && preauthAmount <= 0 {
      preauthAmount = cap
    }
    if paymentFlow != "preauth" &&
        requestedAmount <= 0 &&
        requestedLiters <= 0 {
      paymentFlow = "preauth"
      preauthAmount = cap
    }
    if paymentFlow == "preauth" && preauthAmount <= 0 {
      await handoffFuelOrderFromReorder(order: order, fuel: fuel)
      return
    }
    let amountCents: Int
    if paymentFlow == "preauth" {
      amountCents = preauthAmount
      requestedAmount = 0
    } else if requestedAmount > 0 {
      amountCents = requestedAmount
    } else if requestedLiters > 0 && unitPrice > 0 {
      amountCents = Int((requestedLiters * Double(unitPrice)).rounded())
    } else {
      await handoffFuelOrderFromReorder(order: order, fuel: fuel)
      return
    }
    let fuelPayload: [String: Any] = [
      "fuelGradeId": fuel.fuelGradeId,
      "fuelGradeName": fuel.fuelGradeName ?? "",
      "unit": "liter",
      "unitPriceCents": unitPrice,
      "requestedAmountCents": requestedAmount,
      "requestedLiters": requestedLiters,
      "preauthAmountCents": paymentFlow == "preauth" ? preauthAmount : 0,
      "paymentFlow": paymentFlow
    ]
    do {
      let currency = (order.currency ?? "").isEmpty ? (currentSession?.currency ?? "") : (order.currency ?? "")
      let result = try await client.placeFuelOrder(
        storeId: order.storeId,
        fuel: fuelPayload,
        amountCents: amountCents,
        currency: currency
      )
      await handleFuelPaymentResult(result)
    } catch {
      let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
      let alert = CPAlertTemplate(titleVariants: ["Failed", error.localizedDescription], actions: [done])
      interfaceController?.presentTemplate(alert, animated: true)
    }
  }

  func handleFuelPaymentResult(_ result: CarPlayOrderPaymentResult) async {
    if result.payment.succeeded {
      let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
      let alert = CPAlertTemplate(titleVariants: ["Fuel order placed"], actions: [done])
      interfaceController?.presentTemplate(alert, animated: true)
      return
    }
    if result.payment.requiresAction,
       let link = buildOrderPaymentHandoffLink(orderId: result.orderId, payment: result.payment) {
      sessionStore.saveHandoffLink(link)
      presentHandoffAlert(message: "Open the mobile app to complete payment.")
      return
    }
    let message = result.payment.error ?? "Payment failed"
    let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: ["Failed", message], actions: [done])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func effectiveFuelPreauthCap(session: CarPlaySessionInfo?) -> Int {
    if let cap = session?.fuelPreauthCapCents, cap > 0 { return cap }
    if let storeCap = session?.fuelDefaultPrepayCents, storeCap > 0 { return storeCap }
    return fallbackFuelPrepayCents
  }
}
