import '../models/payment_intent.dart';

class CheckoutIntent {
  final String orderId;
  final String? checkoutUrl;
  final String? paymentId;
  final String? sessionId;

  const CheckoutIntent({
    required this.orderId,
    this.checkoutUrl,
    this.paymentId,
    this.sessionId,
  });
}

abstract class PaymentsAdapter {
  Future<CheckoutIntent?> startCheckout({
    required Map<String, dynamic> orderResponse,
  });

  Future<void> openCheckout(CheckoutIntent intent);

  Future<PaymentIntentInfo?> createPaymentIntent({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    bool? savePaymentMethod,
  });

  Future<void> confirmPaymentIntent(PaymentIntentInfo intent);
}
