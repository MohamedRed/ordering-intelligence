class GroupOrderInvite {
  final String inviteId;
  final String expiresAtIso;

  const GroupOrderInvite({
    required this.inviteId,
    required this.expiresAtIso,
  });

  factory GroupOrderInvite.fromJson(Map<String, dynamic> json) {
    return GroupOrderInvite(
      inviteId: (json['inviteId'] ?? '').toString(),
      expiresAtIso: (json['expiresAt'] ?? '').toString(),
    );
  }
}
