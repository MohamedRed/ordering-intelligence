import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class OrderConfirmation extends StatelessWidget {
  const OrderConfirmation({
    super.key,
    required this.order,
    required this.onNewOrder,
    this.onUpdates,
    this.updatesLabel,
  });

  final Map<String, dynamic> order;
  final VoidCallback onNewOrder;
  final Future<void> Function(String orderId)? onUpdates;
  final String? updatesLabel;

  @override
  Widget build(BuildContext context) {
    final orderId = (order['id'] ?? order['orderId'] ?? '').toString();
    final displayNumber = (order['displayNumber'] ??
            order['display_number'] ??
            order['display'] ??
            '')
        .toString();
    final displayLabel = displayNumber.isNotEmpty ? displayNumber : orderId;
    final hasUpdates = orderId.isNotEmpty && updatesLabel != null && onUpdates != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            Text('Order placed!', style: ShadTheme.of(context).textTheme.h2),
            if (displayLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Order #$displayLabel',
                style: ShadTheme.of(context).textTheme.muted,
              ),
            ],
            if (hasUpdates) ...[
              const SizedBox(height: 16),
              ShadButton.outline(
                onPressed: () async {
                  await onUpdates?.call(orderId);
                },
                child: Text(updatesLabel!),
              ),
            ],
            const SizedBox(height: 16),
            ShadButton(
              onPressed: onNewOrder,
              child: const Text('Start new order'),
            ),
          ],
        ),
      ),
    );
  }
}
