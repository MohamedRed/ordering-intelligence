import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';
import '../../providers/order_detail_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/highlight_provider.dart';
import '../../util/store_id.dart';
import '../../widgets/business_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'fuel_order_section.dart';
import 'order_refund_button.dart';
import 'order_status_action_sheet.dart';

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
    return BusinessScaffold(
      title: Text('Order $orderId'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.refresh(orderDetailProvider(orderId)),
        ),
      ],
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ShadAlert.destructive(
          title: const Text('Failed to load order'),
          description: Text('$err'),
        ),
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
              _StatusPill(status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          Text('Created ${order.createdAt}'),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(order.notes,
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          ShadCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fulfillment', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(order.fulfillmentType.toLowerCase() == 'delivery'
                    ? 'Delivery'
                    : 'Pickup'),
                if (order.fulfillmentType.toLowerCase() == 'delivery' &&
                    order.delivery != null) ...[
                  const SizedBox(height: 10),
                  Text(
                      'Fleet: ${order.delivery!.fleetMode.isEmpty ? 'unknown' : order.delivery!.fleetMode}'),
                ],
              ],
            ),
          ),
          if (order.fulfillmentType.toLowerCase() == 'delivery' &&
              order.delivery != null) ...[
            const SizedBox(height: 16),
            _DeliveryDetailsCard(order: order),
          ],
          if (order.fuel != null) ...[
            const SizedBox(height: 16),
            FuelOrderSection(order: order),
          ],
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Items', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._buildItems(theme, order.items),
          ],
          const SizedBox(height: 12),
          Text('Total: ${order.formattedTotal}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _ActionButtons(order: order, ref: ref),
        ],
      ),
    );
  }

  List<Widget> _buildItems(ThemeData theme, List<OrderItem> items) {
    final unbundled = <OrderItem>[];
    final bundles = <String, List<OrderItem>>{};

    for (final item in items) {
      final bundleId = item.bundleId.trim();
      if (bundleId.isEmpty) {
        unbundled.add(item);
        continue;
      }
      (bundles[bundleId] ??= []).add(item);
    }

    final widgets = <Widget>[];

    for (final item in unbundled) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildItemCard(theme, item),
      ));
    }

    for (final entry in bundles.entries) {
      final bundleItems = List<OrderItem>.from(entry.value)
        ..sort((a, b) => _bundleRoleSortKey(a.bundleRole)
            .compareTo(_bundleRoleSortKey(b.bundleRole)));

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ShadCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bundle: ${entry.key}', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...bundleItems.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildItemCard(
                      theme,
                      item,
                      leadingLabel: item.bundleRole.trim().isEmpty
                          ? null
                          : '${item.bundleRole.trim()}: ',
                    ),
                  )),
            ],
          ),
        ),
      ));
    }

    return widgets;
  }

  Widget _buildItemCard(ThemeData theme, OrderItem item,
      {String? leadingLabel}) {
    final mods = item.modifierLabels;
    final label = leadingLabel ?? '';
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label${item.quantity}× ${item.name}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (mods.isNotEmpty) Text('Mods: ${mods.join(', ')}'),
          Text('Price: \$${(item.priceCents / 100).toStringAsFixed(2)}'),
        ],
      ),
    );
  }
}

class _DeliveryDetailsCard extends StatelessWidget {
  const _DeliveryDetailsCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final delivery = order.delivery;
    if (delivery == null) return const SizedBox.shrink();
    final statusLabel = _deliveryStatusLabel(order);
    final statusKey = _deliveryStatusKey(order);
    final statusColor = _deliveryStatusColor(statusKey);
    final dropoff = delivery.dropoffAddress?.display() ?? '';
    final hasLatLng = delivery.dropoffLatLng != null &&
        (delivery.dropoffLatLng!.lat != 0 || delivery.dropoffLatLng!.lng != 0);

    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery details',
              style: Theme.of(context).textTheme.titleMedium),
          if (statusLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Text('Status: $statusLabel',
                  style: TextStyle(color: statusColor)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
              'Fleet: ${delivery.fleetMode.isEmpty ? 'unknown' : delivery.fleetMode}'),
          if (delivery.assignmentStatus.isNotEmpty)
            Text('Assignment: ${delivery.assignmentStatus}'),
          if (delivery.assignedDriverId.isNotEmpty)
            Text('Driver: ${delivery.assignedDriverId}'),
          if (delivery.providerDeliveryId.isNotEmpty)
            Text('Provider ID: ${delivery.providerDeliveryId}'),
          if (delivery.deliveryStatusSummary.isNotEmpty)
            Text('Status summary: ${delivery.deliveryStatusSummary}'),
          if (dropoff.isNotEmpty) Text('Dropoff: $dropoff'),
          if (dropoff.isEmpty && hasLatLng)
            Text(
                'Dropoff: ${delivery.dropoffLatLng!.lat.toStringAsFixed(4)}, ${delivery.dropoffLatLng!.lng.toStringAsFixed(4)}'),
          if (delivery.quote != null)
            Text('Quote: ${_quoteSummary(delivery.quote!)}'),
          if (delivery.customerPaysDeliveryFee &&
              delivery.deliveryFeeCentsChargedToCustomer > 0)
            Text(
                'Customer fee: ${_money(delivery.deliveryFeeCentsChargedToCustomer)}'),
          if (delivery.trackingUrl.isNotEmpty)
            Text('Tracking: ${delivery.trackingUrl}'),
        ],
      ),
    );
  }
}

String _money(int cents) {
  return '\$${(cents / 100).toStringAsFixed(2)}';
}

String _quoteSummary(DeliveryQuote quote) {
  final provider = quote.provider.isNotEmpty ? quote.provider : 'provider';
  final eta =
      quote.dropoffEtaMinutes > 0 ? '${quote.dropoffEtaMinutes} min' : 'n/a';
  final fee = quote.providerFeeCents > 0 ? _money(quote.providerFeeCents) : '';
  if (fee.isEmpty) return '$provider • ETA $eta';
  return '$provider • ETA $eta • Fee $fee';
}

int _bundleRoleSortKey(String role) {
  switch (role.trim().toLowerCase()) {
    case 'main':
      return 0;
    case 'side':
      return 1;
    case 'drink':
      return 2;
    case 'extra':
      return 3;
    default:
      return 99;
  }
}

String _deliveryStatusKey(Order order) {
  final delivery = order.delivery;
  if (delivery == null) return '';
  final summary = delivery.deliveryStatusSummary.trim().toLowerCase();
  final assignment = delivery.assignmentStatus.trim().toLowerCase();
  final raw = summary.isNotEmpty ? summary : assignment;
  if (raw.contains('out for') ||
      raw.contains('out_for') ||
      raw.contains('en route') ||
      raw.contains('en_route')) {
    return 'out_for_delivery';
  }
  if (raw.contains('delivered')) return 'delivered';
  if (raw.contains('assign')) return 'assigned';
  if (raw.contains('pickup') || raw.contains('picked')) return 'picked_up';
  if (raw.contains('fail') || raw.contains('cancel')) return 'failed';
  if (raw.isNotEmpty) {
    return raw.replaceAll(' ', '_');
  }
  return '';
}

String _deliveryStatusLabel(Order order) {
  final key = _deliveryStatusKey(order);
  switch (key) {
    case 'assigned':
      return 'Assigned';
    case 'picked_up':
      return 'Picked up';
    case 'out_for_delivery':
      return 'Out for delivery';
    case 'delivered':
      return 'Delivered';
    case 'failed':
      return 'Failed';
    case '':
      return '';
    default:
      return key.replaceAll('_', ' ');
  }
}

Color _deliveryStatusColor(String key) {
  switch (key) {
    case 'assigned':
      return Colors.indigo;
    case 'picked_up':
      return Colors.orange;
    case 'out_for_delivery':
      return Colors.deepOrange;
    case 'delivered':
      return Colors.green;
    case 'failed':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.order, required this.ref});
  final Order order;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = _nextActions(order.status);
    final canNotifyDelay = order.status != OrderStatus.cancelled &&
        order.status != OrderStatus.completed;
    final canRefund = order.isCardPayment && order.totalCents > 0;
    if (actions.isEmpty && !canNotifyDelay && !canRefund) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[
      ...actions.map((status) => ShadButton.outline(
            onPressed: () => _handleStatus(context, ref, order.id, status),
            child: Text(_statusLabel(status)),
          )),
      if (canRefund) OrderRefundButton(order: order),
      if (canNotifyDelay)
        ShadButton.outline(
          onPressed: () => _handleDelay(context, ref, order.id),
          child: const Text('Notify delay'),
        ),
    ];
    return Wrap(
      spacing: 8,
      children: children,
    );
  }

  Future<void> _handleStatus(BuildContext context, WidgetRef ref,
      String orderId, OrderStatus status) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      final result = await showOrderStatusActionSheet(
        context: context,
        storeId: effectiveStoreId(),
        status: status,
      );
      if (result == null) return;
      await repo.setStatusWithAction(
        orderId,
        status,
        notifyMode: result.notifyMode,
        note: result.note,
        templateId: result.templateId,
      );
      ref
        ..invalidate(orderDetailProvider(orderId))
        ..invalidate(ordersProvider);
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Order updated',
          message: 'Order $orderId → ${_statusLabel(status)}',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Update failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    }
  }

  Future<void> _handleDelay(
      BuildContext context, WidgetRef ref, String orderId) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      final result = await showOrderDelayActionSheet(
        context: context,
        storeId: effectiveStoreId(),
      );
      if (result == null) return;
      await repo.notifyDelayWithAction(
        orderId,
        notifyMode: result.notifyMode,
        note: result.note,
        templateId: result.templateId,
      );
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Delay notice sent',
          message: 'Customer was notified for order $orderId',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Notify failed',
          message: '$err',
          type: ShadSnackType.error,
        );
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color)),
    );
  }
}
