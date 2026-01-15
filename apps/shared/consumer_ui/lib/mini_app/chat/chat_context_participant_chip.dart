import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ChatParticipantChip extends StatelessWidget {
  const ChatParticipantChip({
    super.key,
    required this.participant,
    required this.active,
    required this.onTap,
  });

  final GroupOrderParticipant participant;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    final name = _resolveName(participant);
    return InkWell(
      onTap: () {
        haptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: active
                  ? theme.colorScheme.primaryForeground
                  : theme.colorScheme.background,
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: theme.textTheme.small.copyWith(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.foreground,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: theme.textTheme.small.copyWith(
                color: active
                    ? theme.colorScheme.primaryForeground
                    : theme.colorScheme.foreground,
              ),
            ),
          ],
        ),
      ),
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
}
