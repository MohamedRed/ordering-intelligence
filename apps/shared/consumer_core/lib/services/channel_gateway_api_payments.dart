part of 'channel_gateway_api.dart';

mixin ChannelGatewayPaymentsApi on ChannelGatewayApiBase {
  Future<List<PaymentMethodSummary>> fetchMobilePaymentMethods({
    required String sessionId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.get(
      _buildUri('/mobile/payment-methods', {
        'sessionId': sessionId,
        if (signature != null) 'signature': signature,
        if (timestamp != null) 'timestamp': timestamp,
      }),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Payment methods failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = payload['methods'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PaymentMethodSummary.fromJson)
        .toList();
  }

  Future<SetupIntentInfo> createMobileSetupIntent({
    required String sessionId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/payment-methods/setup-intent'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Setup intent failed (${response.statusCode})');
    }
    return SetupIntentInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> setMobileDefaultPaymentMethod({
    required String sessionId,
    required String paymentMethodId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/payment-methods/default'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'paymentMethodId': paymentMethodId,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Default payment method failed (${response.statusCode})');
    }
  }

  Future<OffSessionPaymentResult> payMobileOrderWithDefault({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/orders/$orderId/pay-default'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'amountCents': amountCents,
        'currency': currency,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Off-session payment failed (${response.statusCode})');
    }
    return OffSessionPaymentResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<PaymentIntentInfo> createMobileGroupOrderPaymentIntent({
    required String groupOrderId,
    required String sessionId,
    String? participantId,
    String? currency,
    bool? savePaymentMethod,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/group-orders/$groupOrderId/payment-intent'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'participantId': participantId,
        'currency': currency,
        'savePaymentMethod': savePaymentMethod,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Group order payment intent failed (${response.statusCode})',
      );
    }
    return PaymentIntentInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<OffSessionPaymentResult> payMobileGroupOrderWithDefault({
    required String groupOrderId,
    required String sessionId,
    String? participantId,
    String? currency,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/group-orders/$groupOrderId/pay-default'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'participantId': participantId,
        'currency': currency,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Group order off-session failed (${response.statusCode})',
      );
    }
    return OffSessionPaymentResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
