import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class WaitTimeLoadingRow extends StatelessWidget {
  const WaitTimeLoadingRow({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class WaitTimeErrorBlock extends StatelessWidget {
  const WaitTimeErrorBlock({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 6),
        Text('Failed to load: $error',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        ShadButton.outline(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
