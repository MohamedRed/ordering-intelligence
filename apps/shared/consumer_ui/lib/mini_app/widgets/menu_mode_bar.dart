import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class MenuModeBar extends StatelessWidget {
  const MenuModeBar({super.key, this.toggle, this.onOpenMenu});

  final Widget? toggle;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final haptics = MiniAppScope.hapticsOf(context);
    const double buttonWidth = 44;
    final menuButton = onOpenMenu == null
        ? const SizedBox(width: buttonWidth)
        : SizedBox(
            width: buttonWidth,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {
                haptics.selection();
                onOpenMenu?.call();
              },
              child: const Icon(Icons.menu, size: 18),
            ),
          );
    return Row(
      children: [menuButton, const Spacer(), if (toggle != null) toggle!],
    );
  }
}
