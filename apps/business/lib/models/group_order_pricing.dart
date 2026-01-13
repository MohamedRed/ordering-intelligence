import 'group_order_allocation.dart';
import 'group_order_parsing.dart';

class GroupOrderPricing {
  const GroupOrderPricing({
    required this.subtotalCents,
    required this.taxCents,
    required this.feeCents,
    required this.discountCents,
    required this.totalCents,
    required this.allocations,
  });

  final int subtotalCents;
  final int taxCents;
  final int feeCents;
  final int discountCents;
  final int totalCents;
  final List<GroupOrderAllocation> allocations;

  factory GroupOrderPricing.fromJson(Map<String, dynamic> json) {
    final rawAllocations = json['allocations'];
    final allocations = <GroupOrderAllocation>[];
    if (rawAllocations is List) {
      for (final entry in rawAllocations) {
        if (entry is Map<String, dynamic>) {
          allocations.add(GroupOrderAllocation.fromJson(entry));
        } else if (entry is Map) {
          allocations
              .add(GroupOrderAllocation.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    return GroupOrderPricing(
      subtotalCents: parseGroupOrderInt(json['subtotalCents']),
      taxCents: parseGroupOrderInt(json['taxCents']),
      feeCents: parseGroupOrderInt(json['feeCents']),
      discountCents: parseGroupOrderInt(json['discountCents']),
      totalCents: parseGroupOrderInt(json['totalCents']),
      allocations: allocations,
    );
  }
}
