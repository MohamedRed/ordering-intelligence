class DeliveryPartnerStripeStatus {
  DeliveryPartnerStripeStatus({
    required this.accountId,
    required this.status,
    required this.payoutsEnabled,
    required this.chargesEnabled,
    required this.detailsSubmitted,
    required this.currentlyDue,
    required this.pendingVerification,
    required this.pastDue,
    required this.updatedAt,
  });

  final String accountId;
  final String status;
  final bool payoutsEnabled;
  final bool chargesEnabled;
  final bool detailsSubmitted;
  final List<String> currentlyDue;
  final List<String> pendingVerification;
  final List<String> pastDue;
  final DateTime? updatedAt;

  factory DeliveryPartnerStripeStatus.fromJson(Map<String, dynamic> json) {
    final stripe = (json['stripe'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final requirements =
        (stripe['requirements'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return DeliveryPartnerStripeStatus(
      accountId: (stripe['account_id'] ?? '').toString(),
      status: (stripe['status'] ?? '').toString(),
      payoutsEnabled: stripe['payouts_enabled'] == true,
      chargesEnabled: stripe['charges_enabled'] == true,
      detailsSubmitted: stripe['details_submitted'] == true,
      currentlyDue: _stringList(requirements['currently_due']),
      pendingVerification: _stringList(requirements['pending_verification']),
      pastDue: _stringList(requirements['past_due']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is Map && value['seconds'] is int) {
      final seconds = value['seconds'] as int;
      final nanos = value['nanoseconds'] as int? ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + nanos ~/ 1000000, isUtc: true);
    }
    return null;
  }
}
