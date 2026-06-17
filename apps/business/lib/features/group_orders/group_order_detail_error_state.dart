import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class GroupOrderDetailErrorState extends StatelessWidget {
  const GroupOrderDetailErrorState({
    super.key,
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadAlert.destructive(
              title: Text(message),
              description: Text(detail),
            ),
            const SizedBox(height: 12),
            ShadButton.outline(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
