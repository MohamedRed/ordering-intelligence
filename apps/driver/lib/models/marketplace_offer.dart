class MarketplaceOffer {
  const MarketplaceOffer({
    required this.offerId,
    required this.storeId,
    required this.status,
    this.orderId = '',
    this.payoutCents = 0,
    this.currency = '',
    this.dropoffAddress = '',
    this.instructions = '',
    this.selectedDelivererId = '',
    this.expiresAt,
  });

  final String offerId;
  final String storeId;
  final String status;
  final String orderId;
  final int payoutCents;
  final String currency;
  final String dropoffAddress;
  final String instructions;
  final String selectedDelivererId;
  final DateTime? expiresAt;

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    return MarketplaceOffer(
      offerId: (json['offerId'] ?? '').toString(),
      orderId: (json['orderId'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      payoutCents: _toInt(json['payoutCents']),
      currency: (json['currency'] ?? '').toString(),
      dropoffAddress: _pickDropoffAddress(json),
      instructions: (json['instructions'] ?? '').toString(),
      selectedDelivererId: (json['selectedDelivererId'] ?? '').toString(),
      expiresAt: _parseDate(json['expiresAt']),
    );
  }

  static String _pickDropoffAddress(Map<String, dynamic> json) {
    final address = json['dropoffAddress'];
    if (address is Map) {
      final formatted = address['formatted'];
      if (formatted != null && formatted.toString().trim().isNotEmpty) {
        return formatted.toString();
      }
      final line1 = address['line1']?.toString() ?? '';
      final city = address['city']?.toString() ?? '';
      return [line1, city].where((p) => p.trim().isNotEmpty).join(', ');
    }
    return '';
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }
}
