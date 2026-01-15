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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < options.length; index++) ...[
          SizedBox(
            width: double.infinity,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {
                haptics.selection();
                onSelected(options[index]);
              },
              child: Text(options[index].label),
            ),
          ),
          if (index < options.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}
