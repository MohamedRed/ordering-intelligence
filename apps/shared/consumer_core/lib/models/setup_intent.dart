class SetupIntentInfo {
  const SetupIntentInfo({
    required this.setupIntentId,
    required this.clientSecret,
    required this.customerId,
    required this.ephemeralKey,
    required this.stripeAccountId,
    required this.publishableKey,
  });

  final String setupIntentId;
  final String clientSecret;
  final String customerId;
  final String ephemeralKey;
  final String stripeAccountId;
  final String publishableKey;

  factory SetupIntentInfo.fromJson(Map<String, dynamic> json) {
    return SetupIntentInfo(
      setupIntentId: (json['setupIntentId'] ?? json['setup_intent_id'] ?? '').toString(),
      clientSecret: (json['clientSecret'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      ephemeralKey: (json['ephemeralKey'] ?? '').toString(),
      stripeAccountId: (json['stripeAccountId'] ?? '').toString(),
      publishableKey: (json['publishableKey'] ?? '').toString(),
    );
  }
}
