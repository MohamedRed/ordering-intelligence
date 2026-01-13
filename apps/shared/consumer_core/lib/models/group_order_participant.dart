import 'group_order_contact.dart';

class GroupOrderParticipant {
  final String participantId;
  final GroupOrderContact contact;
  final String displayName;

  const GroupOrderParticipant({
    required this.participantId,
    required this.contact,
    required this.displayName,
  });

  factory GroupOrderParticipant.fromJson(Map<String, dynamic> json) {
    return GroupOrderParticipant(
      participantId: (json['participantId'] ?? '').toString(),
      contact: GroupOrderContact.fromJson(
        (json['channelContact'] as Map<String, dynamic>? ?? const {}),
      ),
      displayName: (json['displayName'] ?? '').toString(),
    );
  }
}
