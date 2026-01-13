class GroupOrderContact {
  const GroupOrderContact({
    required this.channel,
    required this.accountId,
    required this.userId,
    required this.displayName,
    required this.metadata,
  });

  final String channel;
  final String accountId;
  final String userId;
  final String displayName;
  final Map<String, dynamic> metadata;

  factory GroupOrderContact.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['metadata'];
    return GroupOrderContact(
      channel: (json['channel'] ?? '').toString(),
      accountId: (json['accountId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      metadata: rawMeta is Map<String, dynamic>
          ? rawMeta
          : rawMeta is Map
              ? rawMeta.cast<String, dynamic>()
              : const {},
    );
  }

  String get label {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (userId.trim().isNotEmpty) return userId.trim();
    if (accountId.trim().isNotEmpty) return accountId.trim();
    if (channel.trim().isNotEmpty) return channel.trim();
    return 'Guest';
  }
}
