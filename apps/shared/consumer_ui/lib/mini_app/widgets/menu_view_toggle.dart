import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../menu_view_mode.dart';

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
    return Row(
      children: [
        _ModeButton(
          label: 'Browse',
          active: mode == MenuViewMode.browse,
          onPressed: () => onChanged(MenuViewMode.browse),
        ),
        const SizedBox(width: 8),
        _ModeButton(
          label: 'Chat',
          active: mode == MenuViewMode.chat,
          onPressed: () => onChanged(MenuViewMode.chat),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (active) {
      return ShadButton(
        size: ShadButtonSize.sm,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
