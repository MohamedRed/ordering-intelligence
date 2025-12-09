import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/order.dart';
import '../../providers/order_detail_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/highlight_provider.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(highlightedOrderIdProvider, (_, next) {
      if (next == orderId) {
        // no-op, highlight already handled upstream
      }
    });

    final orderAsync = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text('Order $orderId'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(orderDetailProvider(orderId)),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load: $err')),
        data: (order) => _OrderBody(order: order),
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.customerName, style: theme.textTheme.titleLarge),
              Chip(
                label: Text(_statusLabel(order.status)),
                backgroundColor: _statusColor(order.status).withOpacity(0.12),
                labelStyle: TextStyle(color: _statusColor(order.status)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Created ${order.createdAt}'),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(order.notes, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          Text('Items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...order.items.map((item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${item.quantity}× ${item.name}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.modifiers.isNotEmpty)
                        Text('Mods: ${item.modifiers.join(', ')}'),
                      Text('Price: \$${(item.priceCents / 100).toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 12),
          Text('Total: ${order.formattedTotal}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _ActionButtons(order: order, ref: ref),
        ],
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.order, required this.ref});
  final Order order;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = _nextActions(order.status);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: actions
          .map((status) => OutlinedButton(
                onPressed: () => _handleStatus(context, ref, order.id, status),
                child: Text(_statusLabel(status)),
              ))
          .toList(),
    );
  }

  Future<void> _handleStatus(BuildContext context, WidgetRef ref,
      String orderId, OrderStatus status) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      await repo.setStatus(orderId, status);
      ref
        ..invalidate(orderDetailProvider(orderId))
        ..invalidate(ordersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Order $orderId updated to ${_statusLabel(status)}')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $err')));
      }
    }
  }
}

Color _statusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Colors.orange;
    case OrderStatus.confirmed:
      return Colors.blue;
    case OrderStatus.ready:
      return Colors.teal;
    case OrderStatus.completed:
      return Colors.green;
    case OrderStatus.cancelled:
      return Colors.grey;
  }
}

String _statusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.confirmed:
      return 'Confirmed';
    case OrderStatus.ready:
      return 'Ready';
    case OrderStatus.completed:
      return 'Completed';
    case OrderStatus.cancelled:
      return 'Cancelled';
  }
}

List<OrderStatus> _nextActions(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return [OrderStatus.confirmed, OrderStatus.cancelled];
    case OrderStatus.confirmed:
      return [OrderStatus.ready, OrderStatus.cancelled];
    case OrderStatus.ready:
      return [OrderStatus.completed, OrderStatus.cancelled];
    case OrderStatus.completed:
    case OrderStatus.cancelled:
      return [];
  }
}
