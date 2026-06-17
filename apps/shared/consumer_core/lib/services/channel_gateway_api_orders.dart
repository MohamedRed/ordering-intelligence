part of 'channel_gateway_api.dart';

mixin ChannelGatewayOrdersApi on ChannelGatewayApiBase {
  Future<Map<String, dynamic>> createOrder({
    required String sessionId,
    required String storeId,
    required List<CartItem> items,
    FuelOrderDraft? fuel,
    String? notes,
    String? locale,
    String? paymentMethod,
    String? successUrl,
    String? cancelUrl,
    String? fulfillmentType,
    DeliveryDraft? delivery,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/orders'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'storeId': storeId,
        'notes': notes,
        'locale': locale,
        'paymentMethod': paymentMethod,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
        'fuel': fuel?.toJson(),
        'fulfillmentType': fulfillmentType,
        'delivery': delivery?.toJson(),
        'items': items
            .map(
              (item) => {
                'itemId': item.item.id,
                'quantity': item.quantity,
                'modifierSelections': item.toModifierSelectionsJson(),
              },
            )
            .toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Order create failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setFuelPumpNumber({
    required String sessionId,
    required String orderId,
    required String pumpNumber,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/orders/$orderId/fuel/pump'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId, 'pumpNumber': pumpNumber}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Pump update failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMobilePaymentIntent({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    bool? savePaymentMethod,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/orders/$orderId/payment-intent'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'amountCents': amountCents,
        'currency': currency,
        'savePaymentMethod': savePaymentMethod,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Payment intent failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<DeliveryPrewarmResult?> prewarmDelivery({
    required String sessionId,
    required String storeId,
    DeliveryLatLng? dropoffLatLng,
    DeliveryAddress? dropoffAddress,
    String? dropoffAddressText,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/delivery/prewarm'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'storeId': storeId,
        'dropoffLatLng': dropoffLatLng?.toJson(),
        'dropoffAddress': dropoffAddress?.toJson(),
        'dropoffAddressText': dropoffAddressText,
      }),
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Delivery prewarm failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    if (payload is Map<String, dynamic>) {
      return DeliveryPrewarmResult.fromJson(payload);
    }
    return null;
  }
}
