part of 'channel_gateway_api.dart';

GroupOrderSession parseGroupOrderResponse(http.Response response) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Group order request failed (${response.statusCode})');
  }
  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  final raw = payload['groupOrder'];
  if (raw is Map<String, dynamic>) {
    return GroupOrderSession.fromJson(raw);
  }
  return GroupOrderSession.fromJson(payload);
}

Map<String, dynamic> mapGroupOrderItem(CartItem item) {
  return {
    'itemId': item.item.id,
    'name': item.item.name,
    'quantity': item.quantity,
    'priceCents': item.item.priceCents,
    'category': item.item.category,
    'modifierSelections': item.toModifierSelectionsJson(),
  };
}
