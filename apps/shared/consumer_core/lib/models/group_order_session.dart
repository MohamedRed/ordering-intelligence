import 'group_order_contact.dart';
import 'group_order_participant.dart';
import 'group_order_pricing.dart';

class GroupOrderSession {
  final String id;
  final String joinCode;
  final String tenantId;
  final String storeId;
  final String status;
  final String paymentMode;
  final String paymentMethod;
  final GroupOrderContact host;
  final List<GroupOrderParticipant> participants;
  final GroupOrderPricing? pricing;
  final String expiresAtIso;

  const GroupOrderSession({
    required this.id,
    required this.joinCode,
    required this.tenantId,
    required this.storeId,
    required this.status,
    required this.paymentMode,
    required this.paymentMethod,
    required this.host,
    required this.participants,
    required this.pricing,
    required this.expiresAtIso,
  });

  factory GroupOrderSession.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    final participants = <GroupOrderParticipant>[];
    if (rawParticipants is List) {
      for (final entry in rawParticipants) {
        if (entry is Map<String, dynamic>) {
          participants.add(GroupOrderParticipant.fromJson(entry));
        }
      }
    }
    final pricingJson = json['pricing'];
    return GroupOrderSession(
      id: (json['id'] ?? json['groupOrderId'] ?? '').toString(),
      joinCode: (json['joinCode'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      paymentMode: (json['paymentMode'] ?? '').toString(),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      host: GroupOrderContact.fromJson(
        (json['host'] as Map<String, dynamic>? ?? const {}),
      ),
      participants: participants,
      pricing: pricingJson is Map<String, dynamic>
          ? GroupOrderPricing.fromJson(pricingJson)
          : null,
      expiresAtIso: (json['expiresAt'] ?? '').toString(),
    );
  }
}
