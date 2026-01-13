class GroupOrderCheckoutResponse {
  final String checkoutUrl;
  final String paymentId;
  final String sessionId;

  const GroupOrderCheckoutResponse({
    required this.checkoutUrl,
    required this.paymentId,
    required this.sessionId,
  });

  factory GroupOrderCheckoutResponse.fromJson(Map<String, dynamic> json) {
    return GroupOrderCheckoutResponse(
      checkoutUrl: (json['checkoutUrl'] ?? '').toString(),
      paymentId: (json['paymentId'] ?? '').toString(),
      sessionId: (json['sessionId'] ?? '').toString(),
    );
  }
}
