import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../models/order.dart';
import 'order_delivery_helpers.dart';
import 'order_list_actions.dart';

class OrderCard extends ConsumerWidget {
  const OrderCard({
    super.key,
    required this.order,
    this.highlighted = false,
  });

  final Order order;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShadCard(
      backgroundColor: highlighted
          ? Colors.orange.shade50
          : ShadTheme.of(context).colorScheme.card,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.title,
                    style: Theme.of(context).textTheme.titleMedium),
                Row(
                  children: [
                    if (order.fulfillmentType.toLowerCase() == 'delivery')
                      const _FulfillmentPill(label: 'Delivery'),
                    _StatusPill(status: order.status),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(order.itemsSummary()),
            if (order.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(order.notes,
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            if (order.fulfillmentType.toLowerCase() == 'delivery') ...[
              const SizedBox(height: 8),
              _DeliveryStatusPill(order: order),
              const SizedBox(height: 8),
              _DeliveryInfoPanel(order: order),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.formattedTotal,
                    style: Theme.of(context).textTheme.titleMedium),
                OrderActionButtons(order: order, ref: ref),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(orderStatusLabel(status), style: TextStyle(color: color)),
    );
  }
}

class _DeliveryStatusPill extends StatelessWidget {
  const _DeliveryStatusPill({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final label = deliveryStatusLabelForOrder(order);
    if (label.isEmpty) return const SizedBox.shrink();
    final key = deliveryStatusKeyForOrder(order);
    final color = deliveryStatusColor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text('Delivery: $label', style: TextStyle(color: color)),
    );
  }
}

class _DeliveryInfoPanel extends StatelessWidget {
  const _DeliveryInfoPanel({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final delivery = order.delivery;
    if (delivery == null) return const SizedBox.shrink();
    final fleet = delivery.fleetMode.isNotEmpty ? delivery.fleetMode : 'unknown';
    final lines = <String>[];
    if (delivery.assignmentStatus.isNotEmpty) {
      lines.add('Assignment: ${delivery.assignmentStatus}');
    }
    if (delivery.assignedDriverId.isNotEmpty) {
      lines.add('Driver: ${delivery.assignedDriverId}');
    }
    if (delivery.providerDeliveryId.isNotEmpty) {
      lines.add('Provider ID: ${delivery.providerDeliveryId}');
    }
    if (delivery.deliveryStatusSummary.isNotEmpty) {
      lines.add('Status: ${delivery.deliveryStatusSummary}');
    }
    final dropoff = delivery.dropoffAddress?.display() ?? '';
    if (dropoff.isNotEmpty) {
      lines.add('Dropoff: $dropoff');
    }
    if (delivery.trackingUrl.isNotEmpty) {
      lines.add('Tracking: ${delivery.trackingUrl}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery details',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text('Fleet: $fleet'),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...lines.map((line) => Text(line)),
          ],
        ],
      ),
    );
  }
}

class _FulfillmentPill extends StatelessWidget {
  const _FulfillmentPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey)),
    );
  }
}
