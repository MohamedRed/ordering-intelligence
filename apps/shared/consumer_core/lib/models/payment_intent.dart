class PaymentIntentInfo {
  final String paymentId;
  final String paymentIntentId;
  final String clientSecret;
  final String customerId;
  final String ephemeralKey;
  final String stripeAccountId;
  final String publishableKey;
  final int amountCents;
  final String currency;

  const PaymentIntentInfo({
    required this.paymentId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.customerId,
    required this.ephemeralKey,
    required this.stripeAccountId,
    required this.publishableKey,
    required this.amountCents,
    required this.currency,
  });

  factory PaymentIntentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentIntentInfo(
      paymentId: (json['paymentId'] ?? '').toString(),
      paymentIntentId: (json['paymentIntentId'] ?? '').toString(),
      clientSecret: (json['clientSecret'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      ephemeralKey: (json['ephemeralKey'] ?? '').toString(),
      stripeAccountId: (json['stripeAccountId'] ?? '').toString(),
      publishableKey: (json['publishableKey'] ?? '').toString(),
      amountCents: (json['amountCents'] ?? 0) is num
          ? (json['amountCents'] as num).toInt()
          : int.tryParse(json['amountCents'].toString()) ?? 0,
      currency: (json['currency'] ?? '').toString(),
    );
  }
}
