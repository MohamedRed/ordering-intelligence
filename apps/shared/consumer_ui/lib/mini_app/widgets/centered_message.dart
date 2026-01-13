import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    super.key,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: ShadTheme.of(context).textTheme.h2),
            const SizedBox(height: 8),
            Text(description, style: ShadTheme.of(context).textTheme.muted),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ShadButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
