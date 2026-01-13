import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_core/consumer_core.dart';

class GroupOrderParticipantsList extends StatelessWidget {
  const GroupOrderParticipantsList({
    super.key,
    required this.participants,
    required this.host,
  });

  final List<GroupOrderParticipant> participants;
  final GroupOrderContact host;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }
    final textTheme = ShadTheme.of(context).textTheme;
    final colorScheme = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Participants (${participants.length})', style: textTheme.muted),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: participants.map((participant) {
            final name = _resolveName(participant);
            final isHost = _isHost(participant);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.muted,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: textTheme.small),
                  if (isHost) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.primary),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Host',
                        style: textTheme.small.copyWith(color: colorScheme.primary),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _resolveName(GroupOrderParticipant participant) {
    final displayName = participant.displayName.trim();
    if (displayName.isNotEmpty) return displayName;
    final contactName = participant.contact.displayName.trim();
    if (contactName.isNotEmpty) return contactName;
    final fallback = participant.participantId.trim();
    if (fallback.isNotEmpty) return fallback;
    return 'Guest';
  }

  bool _isHost(GroupOrderParticipant participant) {
    final hostUserId = host.userId.trim();
    if (hostUserId.isNotEmpty && hostUserId == participant.contact.userId.trim()) {
      return true;
    }
    final hostAccountId = host.accountId.trim();
    if (hostAccountId.isEmpty) return false;
    return hostAccountId == participant.contact.accountId.trim();
  }
}