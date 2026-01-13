import 'group_order_allocation.dart';
import 'group_order_contact.dart';
import 'group_order_participant.dart';
import 'group_order_pricing.dart';
import 'order_delivery.dart';
import 'order_item.dart';

class GroupOrder {
  const GroupOrder({
    required this.id,
    required this.joinCode,
    required this.orderId,
    required this.tenantId,
    required this.storeId,
    required this.customerId,
    required this.fulfillmentType,
    required this.delivery,
    required this.status,
    required this.host,
    required this.participants,
    required this.items,
    required this.pricing,
    required this.paymentMode,
    required this.paymentMethod,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String joinCode;
  final String orderId;
  final String tenantId;
  final String storeId;
  final String customerId;
  final String fulfillmentType;
  final OrderDelivery? delivery;
  final String status;
  final GroupOrderContact host;
  final List<GroupOrderParticipant> participants;
  final List<OrderItem> items;
  final GroupOrderPricing? pricing;
  final String paymentMode;
  final String paymentMethod;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory GroupOrder.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    final participants = <GroupOrderParticipant>[];
    if (rawParticipants is List) {
      for (final entry in rawParticipants) {
        if (entry is Map<String, dynamic>) {
          participants.add(GroupOrderParticipant.fromJson(entry));
        } else if (entry is Map) {
          participants.add(
              GroupOrderParticipant.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    final rawItems = json['items'];
    final items = <OrderItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          items.add(OrderItem.fromJson(entry));
        } else if (entry is Map) {
          items.add(OrderItem.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    final deliveryRaw = json['delivery'];
    final OrderDelivery? delivery = deliveryRaw is Map
        ? OrderDelivery.fromJson(deliveryRaw.cast<String, dynamic>())
        : null;
    final pricingJson = json['pricing'];
    return GroupOrder(
      id: (json['id'] ?? json['groupOrderId'] ?? '').toString(),
      joinCode: (json['joinCode'] ?? '').toString(),
      orderId: (json['orderId'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      customerId: (json['customerId'] ?? '').toString(),
      fulfillmentType: (json['fulfillmentType'] ?? '').toString(),
      delivery: delivery,
      status: (json['status'] ?? '').toString(),
      host: GroupOrderContact.fromJson(
        (json['host'] as Map<String, dynamic>? ?? const {}),
      ),
      participants: participants,
      items: items,
      pricing: pricingJson is Map<String, dynamic>
          ? GroupOrderPricing.fromJson(pricingJson)
          : null,
      paymentMode: (json['paymentMode'] ?? '').toString(),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }

  int get totalCents {
    if (pricing != null && pricing!.totalCents > 0) {
      return pricing!.totalCents;
    }
    if (items.isEmpty) return 0;
    return items.fold<int>(
        0, (sum, item) => sum + (item.priceCents * item.quantity));
  }

  String get formattedTotal {
    if (totalCents <= 0) return '—';
    final value = (totalCents / 100).toStringAsFixed(2);
    return '\$$value';
  }

  String get hostLabel => host.label;
  bool get isCardPayment => paymentMethod.toLowerCase() == 'card';
  bool get isSplitPayment => paymentMode == 'split_by_participant';

  String get paymentModeLabel {
    switch (paymentMode) {
      case 'split_by_participant':
        return 'Split by participant';
      case 'single_payer':
        return 'Single payer';
      default:
        return paymentMode.isEmpty ? 'Unspecified' : paymentMode;
    }
  }

  String get paymentMethodLabel {
    if (paymentMethod.isEmpty) return 'Unspecified';
    return paymentMethod[0].toUpperCase() + paymentMethod.substring(1);
  }

  String itemsSummary({int maxItems = 3}) {
    if (items.isEmpty) return '';
    final summary = items
        .take(maxItems)
        .map((item) => '${item.quantity}x ${item.name}')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (items.length > maxItems) {
      summary.add('+${items.length - maxItems} more');
    }
    return summary.join(', ');
  }

  GroupOrderAllocation? allocationFor(String participantId) {
    final pricing = this.pricing;
    if (pricing == null) return null;
    for (final allocation in pricing.allocations) {
      if (allocation.participantId == participantId) return allocation;
    }
    return null;
  }

  GroupOrderParticipant? participantById(String participantId) {
    for (final participant in participants) {
      if (participant.participantId == participantId) return participant;
    }
    return null;
  }

  String participantLabel(String participantId) {
    final participant = participantById(participantId);
    if (participant != null) return participant.label;
    return participantId;
  }
}
