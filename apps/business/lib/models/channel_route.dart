class ChannelRoute {
  final String id;
  final String channel;
  final String accountId;
  final String tenantId;
  final String storeId;
  final String businessType;
  final String agentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ChannelRoute({
    required this.id,
    required this.channel,
    required this.accountId,
    required this.tenantId,
    required this.storeId,
    required this.businessType,
    required this.agentId,
    this.createdAt,
    this.updatedAt,
  });

  factory ChannelRoute.fromJson(Map<String, dynamic> json) {
    String pickString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null) return value.toString();
      }
      return '';
    }

    DateTime? parseTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return ChannelRoute(
      id: pickString(['id', 'docId']),
      channel: pickString(['channel']),
      accountId: pickString(['accountId', 'account_id']),
      tenantId: pickString(['tenantId', 'tenant_id']),
      storeId: pickString(['storeId', 'store_id']),
      businessType: pickString(['businessType', 'business_type']),
      agentId: pickString(['agentId', 'agent_id']),
      createdAt: parseTime(json['createdAt'] ?? json['created_at']),
      updatedAt: parseTime(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
      'accountId': accountId,
      'tenantId': tenantId,
      'storeId': storeId,
      'businessType': businessType,
      'agentId': agentId,
    };
  }
}
