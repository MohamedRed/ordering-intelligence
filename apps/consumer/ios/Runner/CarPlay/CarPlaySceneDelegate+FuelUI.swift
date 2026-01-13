import CarPlay
import Foundation

extension CarPlaySceneDelegate {
  func buildFuelSection(session: CarPlaySessionInfo) async -> CPListSection? {
    let businessType = (session.businessType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard businessType == "gas_station" else { return nil }
    let storeId = (session.storeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if storeId.isEmpty { return nil }
    let grades = (try? await client.fetchMenu(storeId: storeId)) ?? []
    if grades.isEmpty { return nil }
    let currency = (session.currency ?? "").isEmpty ? "EUR" : (session.currency ?? "").uppercased()
    let preauthCents = effectiveFuelPreauthCap(session: session)

    let listItems = grades.map { grade in
      let title = grade.name.isEmpty ? grade.id : grade.name
      let price = grade.priceCents ?? 0
      let detail = price > 0
        ? "Authorize \(currency) \(formatCents(preauthCents)) • \(currency) \(formatCents(price))/L"
        : "Authorize \(currency) \(formatCents(preauthCents))"
      return CPListItem(text: title, detailText: detail)
    }
    listItems.enumerated().forEach { index, item in
      item.handler = { [weak self] _, completion in
        Task {
          await self?.confirmFuelOrder(
            storeId: storeId,
            grade: grades[index],
            amountCents: preauthCents,
            currency: session.currency ?? ""
          )
          completion()
        }
      }
    }
    return CPListSection(items: listItems)
  }

  func confirmFuelOrder(
    storeId: String,
    grade: CarPlayMenuItem,
    amountCents: Int,
    currency: String
  ) async {
    let title = grade.name.isEmpty ? "Fuel order" : "Fuel order (\(grade.name))"
    let currencyLabel = currency.isEmpty ? "EUR" : currency
    let confirmTitle = hasDefaultPaymentMethod
      ? "Authorize \(currencyLabel) \(formatCents(amountCents))"
      : "Send to phone \(currencyLabel) \(formatCents(amountCents))"
    let confirm = CPAlertAction(title: confirmTitle, style: .default) { [weak self] _ in
      Task {
        guard let self else { return }
        let canPay = await self.ensureDefaultPaymentMethod()
        if !canPay {
          await self.handoffFuelOrder(storeId: storeId, grade: grade, amountCents: amountCents, currency: currency)
          return
        }
        await self.placeFuelOrder(
          storeId: storeId,
          grade: grade,
          amountCents: amountCents,
          currency: currency
        )
      }
    }
    let cancel = CPAlertAction(title: "Cancel", style: .cancel, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: [title], actions: [confirm, cancel])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func confirmFuelReorder(order: CarPlayReorder, fuel: CarPlayFuelOrder) async {
    let grade = fuel.fuelGradeName ?? fuel.fuelGradeId
    let title = grade?.isEmpty == false ? "Fuel reorder (\(grade!))" : "Fuel reorder"
    let confirm = CPAlertAction(title: "Confirm", style: .default) { [weak self] _ in
      Task {
        guard let self else { return }
        let canPay = await self.ensureDefaultPaymentMethod()
        if !canPay {
          await self.handoffFuelOrderFromReorder(order: order, fuel: fuel)
          return
        }
        await self.placeFuelReorder(order: order, fuel: fuel)
      }
    }
    let cancel = CPAlertAction(title: "Cancel", style: .cancel, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: [title], actions: [confirm, cancel])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func handoffFuelOrder(
    storeId: String,
    grade: CarPlayMenuItem,
    amountCents: Int,
    currency: String
  ) async {
    let link = buildFuelHandoffLink(
      storeId: storeId,
      gradeId: grade.id,
      gradeName: grade.name,
      unitPriceCents: grade.priceCents ?? 0,
      paymentFlow: "preauth",
      requestedAmountCents: 0,
      preauthAmountCents: amountCents,
      currency: currency
    )
    sessionStore.saveHandoffLink(link)
    let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: ["Open the mobile app to finish payment"], actions: [done])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func handoffFuelOrderFromReorder(order: CarPlayReorder, fuel: CarPlayFuelOrder) async {
    let link = buildFuelHandoffLink(
      storeId: order.storeId,
      gradeId: fuel.fuelGradeId,
      gradeName: fuel.fuelGradeName ?? "",
      unitPriceCents: fuel.unitPriceCents ?? 0,
      paymentFlow: fuel.paymentFlow ?? "prepay",
      requestedAmountCents: fuel.requestedAmountCents ?? 0,
      requestedLiters: fuel.requestedLiters ?? 0,
      preauthAmountCents: fuel.preauthAmountCents ?? 0,
      currency: order.currency ?? ""
    )
    sessionStore.saveHandoffLink(link)
    let done = CPAlertAction(title: "OK", style: .default, handler: { _ in })
    let alert = CPAlertTemplate(titleVariants: ["Open the mobile app to finish payment"], actions: [done])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  func formatCents(_ cents: Int) -> String {
    return String(format: "%.2f", Double(cents) / 100.0)
  }

  func buildFuelHandoffLink(
    storeId: String,
    gradeId: String,
    gradeName: String,
    unitPriceCents: Int,
    paymentFlow: String,
    requestedAmountCents: Int,
    requestedLiters: Double = 0,
    preauthAmountCents: Int = 0,
    currency: String
  ) -> String {
    var parts: [String] = []
    parts.append("storeId=\(encode(storeId))")
    parts.append("gradeId=\(encode(gradeId))")
    if !gradeName.isEmpty {
      parts.append("gradeName=\(encode(gradeName))")
    }
    if unitPriceCents > 0 {
      parts.append("unitPriceCents=\(unitPriceCents)")
    }
    parts.append("paymentFlow=\(encode(paymentFlow))")
    if requestedAmountCents > 0 {
      parts.append("requestedAmountCents=\(requestedAmountCents)")
    }
    if requestedLiters > 0 {
      parts.append("requestedLiters=\(requestedLiters)")
    }
    if preauthAmountCents > 0 {
      parts.append("preauthAmountCents=\(preauthAmountCents)")
    }
    if !currency.isEmpty {
      parts.append("currency=\(encode(currency))")
    }
    return "com.orderingintelligence.consumer://fuel-order?\(parts.joined(separator: "&"))"
  }
}
