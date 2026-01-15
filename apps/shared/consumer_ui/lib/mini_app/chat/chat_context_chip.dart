import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ChatContextChip extends StatelessWidget {
  const ChatContextChip({
    super.key,
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
    final haptics = MiniAppScope.hapticsOf(context);
    return InkWell(
      onTap: () {
        haptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.small.copyWith(
            color: active
                ? theme.colorScheme.primaryForeground
                : theme.colorScheme.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
