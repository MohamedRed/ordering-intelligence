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
    const double height = 34;
    const double width = 96;
    const double knobWidth = 44;
    return Container(
      height: height,
      width: width,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: isChat ? Alignment.centerRight : Alignment.centerLeft,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: Container(
              width: knobWidth,
              height: height - 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.background,
                borderRadius: BorderRadius.circular((height - 4) / 2),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 6,
                    color: Colors.black.withOpacity(0.08),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _ToggleIconButton(
                icon: Icons.storefront_outlined,
                selected: !isChat,
                onTap: () {
                  haptics.selection();
                  onChanged(MenuViewMode.browse);
                },
              ),
              _ToggleIconButton(
                icon: Icons.chat_bubble_outline,
                selected: isChat,
                onTap: () {
                  haptics.selection();
                  onChanged(MenuViewMode.chat);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = selected
        ? theme.colorScheme.foreground
        : theme.colorScheme.mutedForeground;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(child: Icon(icon, size: 16, color: color)),
      ),
    );
  }
}
