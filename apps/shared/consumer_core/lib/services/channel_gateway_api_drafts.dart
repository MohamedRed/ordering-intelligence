part of 'channel_gateway_api.dart';

class DraftConflictException implements Exception {
  final DraftOrder? latest;

  DraftConflictException({this.latest});

  @override
  String toString() => 'draft_conflict';
}

mixin ChannelGatewayDraftsApi on ChannelGatewayApiBase {
  Future<DraftOrder?> fetchDraftOrder({
    required String sessionId,
    required String storeId,
    required String orderType,
    String? groupOrderId,
  }) async {
    final response = await _client.get(
      _buildWebAppUri(
        '/drafts',
        {
          'sessionId': sessionId,
          'storeId': storeId,
          'orderType': orderType,
          if (groupOrderId != null && groupOrderId.isNotEmpty)
            'groupOrderId': groupOrderId,
        },
      ),
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Draft fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    if (payload is Map<String, dynamic>) {
      final draft = payload['draft'];
      if (draft is Map<String, dynamic>) {
        return DraftOrder.fromJson(draft);
      }
    }
    return null;
  }

  Future<DraftOrder?> upsertDraftOrder({
    required String sessionId,
    required String storeId,
    required String orderType,
    String? groupOrderId,
    required String fulfillmentType,
    required String notes,
    required List<DraftOrderItem> items,
    DraftOrderDelivery? delivery,
    int? version,
  }) async {
    final response = await _client.put(
      _buildWebAppUri('/drafts'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'storeId': storeId,
        'orderType': orderType,
        if (groupOrderId != null && groupOrderId.isNotEmpty)
          'groupOrderId': groupOrderId,
        'fulfillmentType': fulfillmentType,
        'notes': notes,
        'items': items.map((item) => item.toJson()).toList(),
        if (delivery != null) 'delivery': delivery.toJson(),
        if (version != null) 'version': version,
      }),
    );
    if (response.statusCode == 409) {
      final payload = jsonDecode(response.body);
      DraftOrder? latest;
      if (payload is Map<String, dynamic>) {
        final draftJson = payload['draft'];
        if (draftJson is Map<String, dynamic>) {
          latest = DraftOrder.fromJson(draftJson);
        }
      }
      throw DraftConflictException(latest: latest);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Draft update failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body);
    if (payload is Map<String, dynamic>) {
      final draft = payload['draft'];
      if (draft is Map<String, dynamic>) {
        return DraftOrder.fromJson(draft);
      }
    }
    return null;
  }

  Future<void> clearDraftOrder({
    required String sessionId,
    required String storeId,
    required String orderType,
    String? groupOrderId,
  }) async {
    final response = await _client.delete(
      _buildWebAppUri(
        '/drafts',
        {
          'sessionId': sessionId,
          'storeId': storeId,
          'orderType': orderType,
          if (groupOrderId != null && groupOrderId.isNotEmpty)
            'groupOrderId': groupOrderId,
        },
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Draft delete failed (${response.statusCode})');
    }
  }
}
