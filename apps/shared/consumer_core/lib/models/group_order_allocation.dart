import 'group_order_parsing.dart';

class GroupOrderAllocation {
  final String participantId;
  final int subtotalCents;
  final int taxCents;
  final int feeCents;
  final int discountCents;
  final int totalCents;

  const GroupOrderAllocation({
    required this.participantId,
    required this.subtotalCents,
    required this.taxCents,
    required this.feeCents,
    required this.discountCents,
    required this.totalCents,
  });

  factory GroupOrderAllocation.fromJson(Map<String, dynamic> json) {
    return GroupOrderAllocation(
      participantId: (json['participantId'] ?? '').toString(),
      subtotalCents: parseGroupOrderInt(json['subtotalCents']),
      taxCents: parseGroupOrderInt(json['taxCents']),
      feeCents: parseGroupOrderInt(json['feeCents']),
      discountCents: parseGroupOrderInt(json['discountCents']),
      totalCents: parseGroupOrderInt(json['totalCents']),
    );
  }
}
