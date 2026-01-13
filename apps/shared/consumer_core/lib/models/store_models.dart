class StoreChoice {
  final String name;
  final String storeId;
  final String tenantId;
  final String businessType;
  final String logoUrl;
  final String currency;
  final int fuelDefaultPrepayCents;
  final bool deliveryEnabled;
  final String deliveryFleetMode;

  const StoreChoice({
    required this.name,
    required this.storeId,
    required this.tenantId,
    required this.businessType,
    required this.logoUrl,
    this.currency = '',
    this.fuelDefaultPrepayCents = 0,
    this.deliveryEnabled = false,
    this.deliveryFleetMode = '',
  });

  factory StoreChoice.fromJson(Map<String, dynamic> json) {
    final logoUrl =
        (json['logoUrl'] ??
                json['logo_url'] ??
                json['logo'] ??
                json['iconUrl'] ??
                json['icon_url'] ??
                json['imageUrl'] ??
                json['image_url'] ??
                '')
            .toString();
    final deliverySettings =
        (json['delivery_settings'] ?? json['deliverySettings']) as Map?;
    final deliveryEnabled =
        (json['deliveryEnabled'] ??
                json['delivery_enabled'] ??
                deliverySettings?['enabled'])
            ?.toString()
            .toLowerCase() ==
        'true';
    final deliveryFleetMode =
        (json['deliveryFleetMode'] ??
                json['delivery_fleet_mode'] ??
                deliverySettings?['fleet_mode'])
            ?.toString()
            .trim();
    return StoreChoice(
      name: (json['name'] ?? json['storeName'] ?? json['store_name'] ?? '')
          .toString(),
      storeId: (json['storeId'] ?? json['store_id'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? json['tenant_id'] ?? '').toString(),
      businessType: (json['businessType'] ?? json['business_type'] ?? '')
          .toString(),
      logoUrl: logoUrl,
      currency: (json['currency'] ?? json['storeCurrency'] ?? '').toString(),
      fuelDefaultPrepayCents: _toInt(
        json['fuelDefaultPrepayCents'] ??
            json['fuel_default_prepay_cents'] ??
            json['fuel_prepay_default_cents'],
      ),
      deliveryEnabled: deliveryEnabled,
      deliveryFleetMode: deliveryFleetMode ?? '',
    );
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class SessionInfo {
  final String sessionId;
  final String accountId;
  final String userId;
  final String displayName;
  final String storeId;
  final String storeName;
  final String tenantId;
  final String customerId;
  final String businessType;
  final String currency;
  final int fuelDefaultPrepayCents;
  final int fuelPreauthCapCents;
  final bool startGroupOrder;
  final String telegramBotUsername;

  const SessionInfo({
    required this.sessionId,
    required this.accountId,
    required this.userId,
    required this.displayName,
    required this.storeId,
    required this.storeName,
    required this.tenantId,
    this.customerId = '',
    required this.businessType,
    this.currency = '',
    this.fuelDefaultPrepayCents = 0,
    this.fuelPreauthCapCents = 0,
    required this.startGroupOrder,
    required this.telegramBotUsername,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: (json['sessionId'] ?? '').toString(),
      accountId: (json['accountId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      storeName: (json['storeName'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      customerId: (json['customerId'] ?? json['customer_id'] ?? '').toString(),
      businessType: (json['businessType'] ?? '').toString(),
      currency: (json['currency'] ?? '').toString(),
      fuelDefaultPrepayCents: _toInt(
        json['fuelDefaultPrepayCents'] ??
            json['fuel_default_prepay_cents'] ??
            json['fuel_prepay_default_cents'],
      ),
      fuelPreauthCapCents: _toInt(
        json['fuelPreauthCapCents'] ?? json['fuel_preauth_cap_cents'],
      ),
      startGroupOrder:
          json['startGroupOrder'] == true ||
          json['startGroupOrder']?.toString().toLowerCase() == 'true',
      telegramBotUsername:
          (json['telegramBotUsername'] ??
                  json['telegram_bot_username'] ??
                  json['botUsername'] ??
                  '')
              .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'accountId': accountId,
      'userId': userId,
      'displayName': displayName,
      'storeId': storeId,
      'storeName': storeName,
      'tenantId': tenantId,
      'customerId': customerId,
      'businessType': businessType,
      'currency': currency,
      'fuelDefaultPrepayCents': fuelDefaultPrepayCents,
      'fuelPreauthCapCents': fuelPreauthCapCents,
      'startGroupOrder': startGroupOrder,
      'telegramBotUsername': telegramBotUsername,
    };
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
