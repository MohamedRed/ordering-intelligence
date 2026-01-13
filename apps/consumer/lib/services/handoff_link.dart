import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:consumer_core/consumer_core.dart';

import '../models/gas_order_handoff.dart';
import '../models/handoff_payload.dart';
import '../models/order_payment_handoff.dart';
import '../models/reorder_handoff.dart';
import '../models/tv_pairing_handoff.dart';
import 'session_bridge.dart';

class HandoffLinkService {
  HandoffLinkService({AppLinks? appLinks})
      : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  Stream<HandoffPayload> handoffStream() async* {
    await for (final uri in _appLinks.uriLinkStream) {
      final handoff = HandoffLinkParser.parse(uri);
      if (handoff != null) {
        yield handoff;
      }
    }
  }

  Future<HandoffPayload?> consumePendingBridgeLink() async {
    final raw = await SessionBridge.loadHandoffLink();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      await SessionBridge.clearHandoffLink();
      return null;
    }
    final handoff = HandoffLinkParser.parse(uri);
    await SessionBridge.clearHandoffLink();
    return handoff;
  }
}

class HandoffLinkParser {
  static HandoffPayload? parse(Uri uri) {
    final fuel = GasOrderHandoffParser.parse(uri);
    if (fuel != null) return HandoffPayload.fuel(fuel);
    final reorder = ReorderHandoffParser.parse(uri);
    if (reorder != null) return HandoffPayload.reorder(reorder);
    final payment = OrderPaymentHandoffParser.parse(uri);
    if (payment != null) return HandoffPayload.orderPayment(payment);
    final tvPairing = TvPairingHandoffParser.parse(uri);
    if (tvPairing != null) return HandoffPayload.tvPairing(tvPairing);
    return null;
  }
}

class GasOrderHandoffParser {
  static GasOrderHandoff? parse(Uri uri) {
    final target = _target(uri);
    if (target != 'fuel-order') return null;
    final storeId = uri.queryParameters['storeId']?.trim() ?? '';
    final gradeId = uri.queryParameters['gradeId']?.trim() ?? '';
    if (storeId.isEmpty || gradeId.isEmpty) return null;

    final gradeName = uri.queryParameters['gradeName']?.trim() ?? '';
    final unitPriceCents = _parseInt(uri.queryParameters['unitPriceCents']);
    final paymentFlow =
        (uri.queryParameters['paymentFlow'] ?? 'prepay').toLowerCase();
    final requestedAmountCents = _parseInt(
      uri.queryParameters['requestedAmountCents'] ??
          uri.queryParameters['amountCents'],
    );
    final requestedLiters = _parseDouble(
      uri.queryParameters['requestedLiters'] ?? uri.queryParameters['liters'],
    );
    var preauthAmountCents = _parseInt(uri.queryParameters['preauthAmountCents']);
    final currency = uri.queryParameters['currency']?.trim() ?? '';

    if (paymentFlow == FuelPaymentFlow.preauth.value &&
        preauthAmountCents == 0 &&
        requestedAmountCents > 0) {
      preauthAmountCents = requestedAmountCents;
    }

    final fuel = FuelOrderDraft(
      fuelGradeId: gradeId,
      fuelGradeName: gradeName,
      unitPriceCents: unitPriceCents,
      unit: fuelUnitLiter,
      requestedLiters: requestedLiters,
      requestedAmountCents: requestedAmountCents,
      preauthAmountCents: paymentFlow == FuelPaymentFlow.preauth.value
          ? preauthAmountCents
          : 0,
      paymentFlow: paymentFlow == FuelPaymentFlow.preauth.value
          ? FuelPaymentFlow.preauth.value
          : FuelPaymentFlow.prepay.value,
      pumpNumber: '',
    );

    return GasOrderHandoff(
      storeId: storeId,
      fuel: fuel,
      currency: currency,
    );
  }
}

class ReorderHandoffParser {
  static ReorderHandoff? parse(Uri uri) {
    final target = _target(uri);
    if (target != 'reorder') return null;
    final storeId = uri.queryParameters['storeId']?.trim() ?? '';
    if (storeId.isEmpty) return null;
    final items = _parseItems(uri);
    if (items.isEmpty) return null;
    final title = uri.queryParameters['title']?.trim() ?? '';
    final currency = uri.queryParameters['currency']?.trim() ?? '';
    return ReorderHandoff(
      storeId: storeId,
      items: items,
      title: title,
      currency: currency,
    );
  }

  static List<ReorderHandoffItem> _parseItems(Uri uri) {
    final items = <ReorderHandoffItem>[];
    final rawItems = uri.queryParameters['items']?.trim() ?? '';
    if (rawItems.isNotEmpty) {
      for (final entry in rawItems.split(',')) {
        final cleaned = entry.trim();
        if (cleaned.isEmpty) continue;
        final parts = cleaned.split(':');
        final itemId = parts.first.trim();
        if (itemId.isEmpty) continue;
        final qty = parts.length > 1 ? _parseInt(parts[1]) : 1;
        items.add(ReorderHandoffItem(
          itemId: itemId,
          quantity: qty <= 0 ? 1 : qty,
        ));
      }
      return items;
    }

    final ids = uri.queryParametersAll['itemId'] ??
        uri.queryParametersAll['item'] ??
        const [];
    final qtys = uri.queryParametersAll['qty'] ??
        uri.queryParametersAll['quantity'] ??
        const [];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i].trim();
      if (id.isEmpty) continue;
      final qty = i < qtys.length ? _parseInt(qtys[i]) : 1;
      items.add(ReorderHandoffItem(
        itemId: id,
        quantity: qty <= 0 ? 1 : qty,
      ));
    }
    return items;
  }
}

class OrderPaymentHandoffParser {
  static OrderPaymentHandoff? parse(Uri uri) {
    final target = _target(uri);
    if (target != 'order-payment') return null;
    final orderId = uri.queryParameters['orderId']?.trim() ?? '';
    final clientSecret = uri.queryParameters['clientSecret']?.trim() ?? '';
    if (orderId.isEmpty || clientSecret.isEmpty) return null;
    final intent = PaymentIntentInfo(
      paymentId: uri.queryParameters['paymentId']?.trim() ?? '',
      paymentIntentId: uri.queryParameters['paymentIntentId']?.trim() ?? '',
      clientSecret: clientSecret,
      customerId: uri.queryParameters['customerId']?.trim() ?? '',
      ephemeralKey: uri.queryParameters['ephemeralKey']?.trim() ?? '',
      stripeAccountId: uri.queryParameters['stripeAccountId']?.trim() ?? '',
      publishableKey: uri.queryParameters['publishableKey']?.trim() ?? '',
      amountCents: _parseInt(uri.queryParameters['amountCents']),
      currency: uri.queryParameters['currency']?.trim() ?? '',
    );
    return OrderPaymentHandoff(orderId: orderId, intent: intent);
  }
}

class TvPairingHandoffParser {
  static TvPairingHandoff? parse(Uri uri) {
    final target = _target(uri);
    if (target != 'tv-pair' && target != 'tv-pairing') return null;
    final code = uri.queryParameters['code']?.trim() ?? '';
    final pairingId = uri.queryParameters['pairingId']?.trim();
    if (code.isEmpty && (pairingId == null || pairingId.isEmpty)) {
      return null;
    }
    return TvPairingHandoff(code: code, pairingId: pairingId);
  }
}

String _target(Uri uri) {
  if (uri.host.isNotEmpty) return uri.host;
  final path = uri.path.replaceAll('/', '').trim();
  return path;
}

int _parseInt(String? value) {
  if (value == null || value.isEmpty) return 0;
  return int.tryParse(value) ?? 0;
}

double _parseDouble(String? value) {
  if (value == null || value.isEmpty) return 0;
  return double.tryParse(value.replaceAll(',', '.')) ?? 0;
}
