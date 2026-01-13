import 'group_order_contact.dart';

class GroupOrderCreatePayload {
  final String tenantId;
  final String storeId;
  final String paymentMode;
  final GroupOrderContact host;
  final String? participantId;
  final String? displayName;

  const GroupOrderCreatePayload({
    required this.tenantId,
    required this.storeId,
    required this.paymentMode,
    required this.host,
    this.participantId,
    this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'tenantId': tenantId,
      'storeId': storeId,
      'paymentMode': paymentMode,
      'host': {
        'channel': host.channel,
        'accountId': host.accountId,
        'userId': host.userId,
        'displayName': host.displayName,
      },
      if (participantId != null) 'participantId': participantId,
      if (displayName != null) 'displayName': displayName,
    };
  }
}

class GroupOrderJoinPayload {
  final GroupOrderContact contact;
  final String? participantId;
  final String? displayName;

  const GroupOrderJoinPayload({
    required this.contact,
    this.participantId,
    this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'channelContact': {
        'channel': contact.channel,
        'accountId': contact.accountId,
        'userId': contact.userId,
        'displayName': contact.displayName,
      },
      if (participantId != null) 'participantId': participantId,
      if (displayName != null) 'displayName': displayName,
    };
  }
}
