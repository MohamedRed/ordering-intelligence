import 'group_order_contact.dart';

class GroupOrderParticipant {
  const GroupOrderParticipant({
    required this.participantId,
    required this.contact,
    required this.displayName,
  });

  final String participantId;
  final GroupOrderContact contact;
  final String displayName;

  factory GroupOrderParticipant.fromJson(Map<String, dynamic> json) {
    return GroupOrderParticipant(
      participantId: (json['participantId'] ?? '').toString(),
      contact: GroupOrderContact.fromJson(
        (json['channelContact'] as Map<String, dynamic>? ?? const {}),
      ),
      displayName: (json['displayName'] ?? '').toString(),
    );
  }

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    final contactLabel = contact.label;
    return contactLabel.isNotEmpty ? contactLabel : participantId;
  }
}
