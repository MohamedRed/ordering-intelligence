import 'package:consumer_core/consumer_core.dart';

import '../telegram/telegram_webapp_links.dart';

class WebPaymentsAdapter implements PaymentsAdapter {
  @override
  Future<CheckoutIntent?> startCheckout({required Map<String, dynamic> orderResponse}) async {
    final orderId = (orderResponse['id'] ?? '').toString();
    if (orderId.isEmpty) {
      return null;
    }
    return CheckoutIntent(
      orderId: orderId,
      checkoutUrl: orderResponse['checkoutUrl']?.toString(),
      paymentId: orderResponse['paymentId']?.toString(),
      sessionId: orderResponse['sessionId']?.toString(),
    );
  }

  @override
  Future<void> openCheckout(CheckoutIntent intent) async {
    final checkoutUrl = intent.checkoutUrl ?? '';
    if (checkoutUrl.isEmpty) {
      return;
    }
    TelegramWebAppLinks.openLink(checkoutUrl);
  }

  @override
  Future<PaymentIntentInfo?> createPaymentIntent({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    bool? savePaymentMethod,
  }) async {
    return null;
  }

  @override
  Future<void> confirmPaymentIntent(PaymentIntentInfo intent) async {
    return;
  }
}
