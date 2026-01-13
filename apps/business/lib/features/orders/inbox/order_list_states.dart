import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class OrderListEmptyState extends StatelessWidget {
  const OrderListEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.onRefresh,
    this.icon,
  });

  final String title;
  final String message;
  final VoidCallback onRefresh;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon ?? Icons.inbox_outlined,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                ShadButton.outline(
                  onPressed: onRefresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrderListErrorState extends StatelessWidget {
  const OrderListErrorState({
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
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadAlert.destructive(
              title: Text(message),
              description: Text(detail,
                  maxLines: 3, overflow: TextOverflow.ellipsis),
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
