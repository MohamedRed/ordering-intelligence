import 'payment_intent.dart';

class OffSessionPaymentResult {
  const OffSessionPaymentResult({
    required this.status,
    this.intent,
    this.error,
  });

  final String status;
  final PaymentIntentInfo? intent;
  final String? error;

  bool get requiresAction => status == 'requires_action';

  bool get succeeded =>
      status == 'succeeded' || status == 'requires_capture' || status == 'processing';

  factory OffSessionPaymentResult.fromJson(Map<String, dynamic> json) {
    final intentJson = json['intent'];
    final fallbackIntent =
        json['paymentIntentId'] != null || json['clientSecret'] != null ? json : null;
    PaymentIntentInfo? intent;
    if (intentJson is Map<String, dynamic>) {
      intent = PaymentIntentInfo.fromJson(intentJson);
    } else if (fallbackIntent is Map<String, dynamic>) {
      intent = PaymentIntentInfo.fromJson(fallbackIntent);
    }
    return OffSessionPaymentResult(
      status: (json['status'] ?? '').toString(),
      intent: intent,
      error: json['error']?.toString(),
    );
  }
}
