import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';
import 'fuel_order_section.dart';
import 'order_detail_actions.dart';
import 'order_detail_delivery_card.dart';
import 'order_detail_items_section.dart';
import 'order_status_helpers.dart';

class OrderDetailBody extends StatelessWidget {
  const OrderDetailBody({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelivery = order.fulfillmentType.toLowerCase() == 'delivery';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OrderHeader(order: order),
          const SizedBox(height: 8),
          Text('Created ${order.createdAt}'),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              order.notes,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),
          _FulfillmentCard(order: order, isDelivery: isDelivery),
          if (isDelivery && order.delivery != null) ...[
            const SizedBox(height: 16),
            OrderDetailDeliveryCard(order: order),
          ],
          if (order.fuel != null) ...[
            const SizedBox(height: 16),
            FuelOrderSection(order: order),
          ],
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            OrderDetailItemsSection(items: order.items),
          ],
          const SizedBox(height: 12),
          Text('Total: ${order.formattedTotal}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          OrderDetailActions(order: order),
        ],
      ),
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          order.customerName,
          style: Theme.of(context).textTheme.titleLarge,
          softWrap: true,
        );
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 8),
              OrderStatusPill(status: order.status),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            OrderStatusPill(status: order.status),
          ],
        );
      },
    );
  }
}

class _FulfillmentCard extends StatelessWidget {
  const _FulfillmentCard({
    required this.order,
    required this.isDelivery,
  });

  final Order order;
  final bool isDelivery;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fulfillment', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(isDelivery ? 'Delivery' : 'Pickup'),
          if (isDelivery && order.delivery != null) ...[
            const SizedBox(height: 10),
            Text(
              'Fleet: ${order.delivery!.fleetMode.isEmpty ? 'unknown' : order.delivery!.fleetMode}',
            ),
          ],
        ],
      ),
    );
  }
}
