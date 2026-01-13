import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ChatSegmentedControl extends StatelessWidget {
  const ChatSegmentedControl({
    super.key,
    required this.segment,
    required this.onChanged,
    this.chatLabel = 'Chat',
    this.browseLabel = 'Browse',
  });

  final MiniAppSegment segment;
  final ValueChanged<MiniAppSegment> onChanged;
  final String chatLabel;
  final String browseLabel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.of(context).haptics;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: chatLabel,
            active: segment == MiniAppSegment.chat,
            onTap: () {
              if (segment == MiniAppSegment.chat) return;
              haptics.selection();
              onChanged(MiniAppSegment.chat);
            },
          ),
          _SegmentButton(
            label: browseLabel,
            active: segment == MiniAppSegment.browse,
            onTap: () {
              if (segment == MiniAppSegment.browse) return;
              haptics.selection();
              onChanged(MiniAppSegment.browse);
            },
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final textStyle = theme.textTheme.small.copyWith(
      color: active
          ? theme.colorScheme.primaryForeground
          : theme.colorScheme.foreground,
      fontWeight: FontWeight.w600,
    );
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(child: Text(label, style: textStyle)),
          ),
        ),
      ),
    );
  }
}
