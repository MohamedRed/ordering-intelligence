class Tenant {
  final String id;
  final String name;
  final String primaryUser;
  final String status;
  final Map<String, bool> featureFlags;
  final String storeId;
  final String businessType;
  final String timezone;
  final String phone;

  Tenant({
    required this.id,
    required this.name,
    required this.primaryUser,
    required this.status,
    required this.featureFlags,
    required this.storeId,
    required this.businessType,
    required this.timezone,
    required this.phone,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      primaryUser: json['primaryUser'] ?? '',
      status: json['status'] ?? 'active',
      featureFlags: (json['featureFlags'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v == true)),
      storeId: json['storeId'] ?? '',
      businessType: json['businessType'] ?? '',
      timezone: json['timezone'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}
