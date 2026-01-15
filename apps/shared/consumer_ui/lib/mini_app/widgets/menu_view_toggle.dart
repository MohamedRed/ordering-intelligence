import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../menu_view_mode.dart';
import '../mini_app_scope.dart';

class MenuViewToggle extends StatelessWidget {
  const MenuViewToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final MenuViewMode mode;
  final ValueChanged<MenuViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isChat = mode == MenuViewMode.chat;
    final haptics = MiniAppScope.hapticsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Browse',
          style: theme.textTheme.small.copyWith(
            color: isChat
                ? theme.colorScheme.mutedForeground
                : theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(width: 10),
        Switch.adaptive(
          value: isChat,
          activeColor: theme.colorScheme.primary,
          onChanged: (value) {
            haptics.selection();
            onChanged(value ? MenuViewMode.chat : MenuViewMode.browse);
          },
        ),
        const SizedBox(width: 10),
        Text(
          'Chat',
          style: theme.textTheme.small.copyWith(
            color: isChat
                ? theme.colorScheme.foreground
                : theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}
