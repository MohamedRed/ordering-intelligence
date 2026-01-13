DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

class CustomerProfileIdentity {
  final String channel;
  final String userId;
  final String displayName;
  final DateTime? linkedAt;
  final DateTime? lastSeenAt;

  const CustomerProfileIdentity({
    required this.channel,
    required this.userId,
    required this.displayName,
    required this.linkedAt,
    required this.lastSeenAt,
  });

  factory CustomerProfileIdentity.fromJson(Map<String, dynamic> json) {
    return CustomerProfileIdentity(
      channel: (json['channel'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      linkedAt: _parseDate(json['linkedAt']),
      lastSeenAt: _parseDate(json['lastSeenAt']),
    );
  }
}

class CustomerProfile {
  final String customerId;
  final String tenantId;
  final String displayName;
  final String status;
  final DateTime? linkedConsentAt;
  final DateTime? firstSeenAt;
  final String firstSeenChannel;
  final String firstSeenStoreId;
  final String firstSeenPlatform;
  final String firstSeenProvider;
  final List<CustomerProfileIdentity> linkedChannels;
  final DateTime? lastSeenAt;
  final String lastSeenChannel;
  final String lastSeenStoreId;
  final String lastSeenPlatform;
  final String lastSeenProvider;
  final int fuelPreauthCapCents;

  const CustomerProfile({
    required this.customerId,
    required this.tenantId,
    required this.displayName,
    required this.status,
    required this.linkedConsentAt,
    required this.firstSeenAt,
    required this.firstSeenChannel,
    required this.firstSeenStoreId,
    required this.firstSeenPlatform,
    required this.firstSeenProvider,
    required this.linkedChannels,
    required this.lastSeenAt,
    required this.lastSeenChannel,
    required this.lastSeenStoreId,
    required this.lastSeenPlatform,
    required this.lastSeenProvider,
    this.fuelPreauthCapCents = 0,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    final channels = (json['linkedChannels'] as List?)
            ?.map((item) => CustomerProfileIdentity.fromJson(
                item as Map<String, dynamic>))
            .toList() ??
        const <CustomerProfileIdentity>[];
    return CustomerProfile(
      customerId: (json['customerId'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      linkedConsentAt: _parseDate(json['linkedConsentAt']),
      firstSeenAt: _parseDate(json['firstSeenAt']),
      firstSeenChannel: (json['firstSeenChannel'] ?? '').toString(),
      firstSeenStoreId: (json['firstSeenStoreId'] ?? '').toString(),
      firstSeenPlatform: (json['firstSeenPlatform'] ?? '').toString(),
      firstSeenProvider: (json['firstSeenProvider'] ?? '').toString(),
      linkedChannels: channels,
      lastSeenAt: _parseDate(json['lastSeenAt']),
      lastSeenChannel: (json['lastSeenChannel'] ?? '').toString(),
      lastSeenStoreId: (json['lastSeenStoreId'] ?? '').toString(),
      lastSeenPlatform: (json['lastSeenPlatform'] ?? '').toString(),
      lastSeenProvider: (json['lastSeenProvider'] ?? '').toString(),
      fuelPreauthCapCents: _toInt(json['fuelPreauthCapCents']),
    );
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class LinkToken {
  final String token;
  final String targetChannel;
  final String customerId;
  final DateTime? expiresAt;

  const LinkToken({
    required this.token,
    required this.targetChannel,
    required this.customerId,
    required this.expiresAt,
  });

  factory LinkToken.fromJson(Map<String, dynamic> json) {
    return LinkToken(
      token: (json['token'] ?? '').toString(),
      targetChannel: (json['targetChannel'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      expiresAt: _parseDate(json['expiresAt']),
    );
  }
}
