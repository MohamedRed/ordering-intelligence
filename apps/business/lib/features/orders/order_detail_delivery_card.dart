import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';
import 'order_delivery_helpers.dart';

class OrderDetailDeliveryCard extends StatelessWidget {
  const OrderDetailDeliveryCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final delivery = order.delivery;
    if (delivery == null) return const SizedBox.shrink();

    final statusLabel = deliveryStatusLabel(order);
    final statusKey = deliveryStatusKey(order);
    final statusColor = deliveryStatusColor(statusKey);
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
              'Dropoff: ${delivery.dropoffLatLng!.lat.toStringAsFixed(4)}, ${delivery.dropoffLatLng!.lng.toStringAsFixed(4)}',
            ),
          if (delivery.quote != null)
            Text('Quote: ${quoteSummary(delivery.quote!)}'),
          if (delivery.customerPaysDeliveryFee &&
              delivery.deliveryFeeCentsChargedToCustomer > 0)
            Text(
              'Customer fee: ${formatOrderMoney(delivery.deliveryFeeCentsChargedToCustomer)}',
            ),
          if (delivery.trackingUrl.isNotEmpty)
            Text('Tracking: ${delivery.trackingUrl}'),
        ],
      ),
    );
  }
}
