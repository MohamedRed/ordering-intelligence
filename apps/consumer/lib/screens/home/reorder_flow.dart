import 'package:consumer_core/consumer_core.dart';

import '../../adapters/mobile_payments_adapter.dart';

class ReorderFlow {
  ReorderFlow({required this.api, required this.session});

  final ChannelGatewayApi api;
  final SessionInfo session;

  Future<void> placeReorder({
    required RecommendedOrder order,
    required String paymentMethod,
  }) async {
    if (order.isFuelOrder && order.fuel != null) {
      await _placeFuelReorder(order, paymentMethod: paymentMethod);
      return;
    }
    final menu = await api.fetchMenu(order.storeId);
    final applied = ReorderLogic.apply(
      menu: menu,
      cart: const <CartItem>[],
      order: order,
    );
    if (applied.cart.isEmpty) {
      throw Exception('Nothing available to reorder.');
    }
    final response = await api.createOrder(
      sessionId: session.sessionId,
      storeId: order.storeId,
      items: applied.cart,
      paymentMethod: paymentMethod,
    );
    if (paymentMethod == 'card') {
      final adapter = MobilePaymentsAdapter(api: api);
      final intent = await adapter.createPaymentIntent(
        orderId: (response['id'] ?? '').toString(),
        sessionId: session.sessionId,
      );
      if (intent != null) {
        await adapter.confirmPaymentIntent(intent);
      }
    }
  }

  Future<void> _placeFuelReorder(
    RecommendedOrder order, {
    required String paymentMethod,
  }) async {
    final fuel = order.fuel!;
    if (paymentMethod != 'card') {
      throw Exception('Fuel orders require card payment.');
    }
    final response = await api.createOrder(
      sessionId: session.sessionId,
      storeId: order.storeId,
      items: const [],
      fuel: fuel,
      paymentMethod: 'card',
    );
    final orderId = (response['id'] ?? '').toString();
    if (orderId.isEmpty) {
      throw Exception('Fuel order failed.');
    }
    final amountCents = _resolveFuelAmountCents(fuel);
    final adapter = MobilePaymentsAdapter(api: api);
    final intent = await adapter.createPaymentIntent(
      orderId: orderId,
      sessionId: session.sessionId,
      amountCents: amountCents > 0 ? amountCents : null,
      currency: order.currency.isNotEmpty ? order.currency : fuelCurrency,
    );
    if (intent != null) {
      await adapter.confirmPaymentIntent(intent);
    }
  }

  int _resolveFuelAmountCents(FuelOrderDraft fuel) {
    final flow = fuel.paymentFlow.toLowerCase();
    if (flow == FuelPaymentFlow.preauth.value) {
      if (fuel.preauthAmountCents > 0) {
        return fuel.preauthAmountCents;
      }
      if (session.fuelPreauthCapCents > 0) {
        return session.fuelPreauthCapCents;
      }
      return session.fuelDefaultPrepayCents;
    }
    if (fuel.requestedAmountCents > 0) {
      return fuel.requestedAmountCents;
    }
    if (fuel.requestedLiters > 0 && fuel.unitPriceCents > 0) {
      return (fuel.requestedLiters * fuel.unitPriceCents).round();
    }
    return 0;
  }
}
