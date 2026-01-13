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
    final haptics = MiniAppScope.of(context).haptics;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        return ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () {
            haptics.selection();
            onSelected(option);
          },
          child: Text(option.label),
        );
      }).toList(),
    );
  }
}
