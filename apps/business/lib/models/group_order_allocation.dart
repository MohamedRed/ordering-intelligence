import 'group_order_parsing.dart';

class GroupOrderAllocation {
  const GroupOrderAllocation({
    required this.participantId,
    required this.subtotalCents,
    required this.feeCents,
    required this.taxCents,
    required this.discountCents,
    required this.totalCents,
  });

  final String participantId;
  final int subtotalCents;
  final int feeCents;
  final int taxCents;
  final int discountCents;
  final int totalCents;

  factory GroupOrderAllocation.fromJson(Map<String, dynamic> json) {
    return GroupOrderAllocation(
      participantId: (json['participantId'] ?? '').toString(),
      subtotalCents: parseGroupOrderInt(json['subtotalCents']),
      feeCents: parseGroupOrderInt(json['feeCents']),
      taxCents: parseGroupOrderInt(json['taxCents']),
      discountCents: parseGroupOrderInt(json['discountCents']),
      totalCents: parseGroupOrderInt(json['totalCents']),
    );
  }
}
