class GroupOrderContact {
  final String channel;
  final String accountId;
  final String userId;
  final String displayName;

  const GroupOrderContact({
    required this.channel,
    required this.accountId,
    required this.userId,
    required this.displayName,
  });

  factory GroupOrderContact.fromJson(Map<String, dynamic> json) {
    return GroupOrderContact(
      channel: (json['channel'] ?? '').toString(),
      accountId: (json['accountId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
    );
  }
}
