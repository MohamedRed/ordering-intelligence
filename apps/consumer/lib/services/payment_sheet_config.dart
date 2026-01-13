import 'package:consumer_core/consumer_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class PaymentSheetConfig {
  PaymentSheetConfig({
    required this.merchantDisplayName,
    this.merchantIdentifier,
    this.applePay,
    this.googlePay,
  });

  final String merchantDisplayName;
  final String? merchantIdentifier;
  final PaymentSheetApplePay? applePay;
  final PaymentSheetGooglePay? googlePay;

  static PaymentSheetConfig fromIntent(PaymentIntentInfo intent) {
    const merchantName = String.fromEnvironment(
      'STRIPE_MERCHANT_NAME',
      defaultValue: 'Ordering Intelligence',
    );
    const appleMerchantId = String.fromEnvironment('APPLE_PAY_MERCHANT_ID');
    const appleCountryCode = String.fromEnvironment(
      'APPLE_PAY_COUNTRY_CODE',
      defaultValue: 'US',
    );
    const googleCountryCode = String.fromEnvironment(
      'GOOGLE_PAY_COUNTRY_CODE',
      defaultValue: 'US',
    );
    const googlePayEnabledRaw = String.fromEnvironment(
      'GOOGLE_PAY_ENABLED',
      defaultValue: 'true',
    );
    const googlePayTestEnvRaw = String.fromEnvironment(
      'GOOGLE_PAY_TEST_ENV',
      defaultValue: 'true',
    );
    const googlePayLabel = String.fromEnvironment(
      'GOOGLE_PAY_LABEL',
      defaultValue: 'Ordering Intelligence',
    );

    final applePay = appleMerchantId.isNotEmpty
        ? const PaymentSheetApplePay(merchantCountryCode: appleCountryCode)
        : null;
    final rawCurrency = intent.currency.trim();
    final currency = rawCurrency.isEmpty ? null : rawCurrency.toUpperCase();

    final googlePayEnabled =
        _parseBool(googlePayEnabledRaw, fallback: true);
    final googlePay = googlePayEnabled
        ? PaymentSheetGooglePay(
            merchantCountryCode: googleCountryCode,
            currencyCode: currency,
            testEnv: _parseBool(googlePayTestEnvRaw, fallback: true),
            label: googlePayLabel,
          )
        : null;

    return PaymentSheetConfig(
      merchantDisplayName: merchantName,
      merchantIdentifier: appleMerchantId.isNotEmpty ? appleMerchantId : null,
      applePay: applePay,
      googlePay: googlePay,
    );
  }

  static bool _parseBool(String raw, {required bool fallback}) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return fallback;
    return value == 'true' || value == '1' || value == 'yes';
  }
}
