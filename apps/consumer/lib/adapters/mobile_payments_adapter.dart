import 'package:consumer_core/consumer_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../services/payment_sheet_config.dart';

class MobilePaymentsAdapter implements PaymentsAdapter {
  MobilePaymentsAdapter({required this.api});

  final ChannelGatewayApi api;

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
    // Mobile checkout handled by Stripe SDK via payment intents.
  }

  @override
  Future<PaymentIntentInfo?> createPaymentIntent({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    bool? savePaymentMethod,
  }) async {
    final payload = await api.createMobilePaymentIntent(
      orderId: orderId,
      sessionId: sessionId,
      amountCents: amountCents,
      currency: currency,
      savePaymentMethod: savePaymentMethod,
    );
    return PaymentIntentInfo.fromJson(payload);
  }

  @override
  Future<void> confirmPaymentIntent(PaymentIntentInfo intent) async {
    if (intent.clientSecret.isEmpty) {
      throw Exception('Missing payment intent client secret.');
    }
    final publishableKey = intent.publishableKey.isNotEmpty
        ? intent.publishableKey
        : const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
    if (publishableKey.isNotEmpty) {
      Stripe.publishableKey = publishableKey;
    }
    if (intent.stripeAccountId.isNotEmpty) {
      Stripe.stripeAccountId = intent.stripeAccountId;
    }
    final config = PaymentSheetConfig.fromIntent(intent);
    if (config.merchantIdentifier != null &&
        config.merchantIdentifier!.isNotEmpty) {
      Stripe.merchantIdentifier = config.merchantIdentifier;
    }
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: intent.clientSecret,
        customerId: intent.customerId.isEmpty ? null : intent.customerId,
        customerEphemeralKeySecret:
            intent.ephemeralKey.isEmpty ? null : intent.ephemeralKey,
        merchantDisplayName: config.merchantDisplayName,
        applePay: config.applePay,
        googlePay: config.googlePay,
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }

  Future<void> confirmSetupIntent(SetupIntentInfo intent) async {
    if (intent.clientSecret.isEmpty) {
      throw Exception('Missing setup intent client secret.');
    }
    final publishableKey = intent.publishableKey.isNotEmpty
        ? intent.publishableKey
        : const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
    if (publishableKey.isNotEmpty) {
      Stripe.publishableKey = publishableKey;
    }
    if (intent.stripeAccountId.isNotEmpty) {
      Stripe.stripeAccountId = intent.stripeAccountId;
    }
    const merchantName = String.fromEnvironment(
      'STRIPE_MERCHANT_NAME',
      defaultValue: 'Ordering Intelligence',
    );
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        setupIntentClientSecret: intent.clientSecret,
        customerId: intent.customerId.isEmpty ? null : intent.customerId,
        customerEphemeralKeySecret:
            intent.ephemeralKey.isEmpty ? null : intent.ephemeralKey,
        merchantDisplayName: merchantName,
      ),
    );
    await Stripe.instance.presentPaymentSheet();
  }
}
