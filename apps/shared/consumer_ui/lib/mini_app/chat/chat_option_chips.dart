import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';

class ChatOptionChips extends StatelessWidget {
  const ChatOptionChips({
    super.key,
    required this.options,
    required this.onSelected,
  });

  final List<ChatOption> options;
  final ValueChanged<ChatOption> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final haptics = MiniAppScope.hapticsOf(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () {
              haptics.selection();
              onSelected(option);
            },
            child: Text(option.label),
          );
        },
      ),
    );
  }
}
