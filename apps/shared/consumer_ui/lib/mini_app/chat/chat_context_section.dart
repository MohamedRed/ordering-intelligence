import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ChatContextSection extends StatelessWidget {
  const ChatContextSection({
    super.key,
    required this.label,
    required this.child,
  });

  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final showLabel = label != null && label!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(label!, style: theme.textTheme.muted),
          const SizedBox(height: 6),
        ],
        child,
      ],
    );
  }
}
