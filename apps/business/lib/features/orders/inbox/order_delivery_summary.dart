import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../models/order.dart';
import 'order_delivery_helpers.dart';

class OrderDeliverySummary extends StatelessWidget {
  const OrderDeliverySummary({super.key, required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'assigned': 0,
      'picked_up': 0,
      'out_for_delivery': 0,
      'delivered': 0,
      'failed': 0,
      'other': 0,
    };
    for (final order in orders) {
      final key = deliveryStatusKeyForOrder(order);
      if (counts.containsKey(key)) {
        counts[key] = counts[key]! + 1;
      } else if (key.isNotEmpty) {
        counts['other'] = counts['other']! + 1;
      }
    }
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Delivery summary'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _summaryChip('Total', orders.length),
              _summaryChip('Assigned', counts['assigned']!),
              _summaryChip('Picked up', counts['picked_up']!),
              _summaryChip('Out', counts['out_for_delivery']!),
              _summaryChip('Delivered', counts['delivered']!),
              _summaryChip('Failed', counts['failed']!),
              if (counts['other']! > 0) _summaryChip('Other', counts['other']!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text('$label: $value'),
    );
  }
}

class DeliveryStatusChips extends StatelessWidget {
  const DeliveryStatusChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = [
      'all',
      'assigned',
      'picked_up',
      'out_for_delivery',
      'delivered',
      'failed',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options
          .map((opt) => ChoiceChip(
                label: Text(opt.replaceAll('_', ' ').toUpperCase()),
                selected: selected == opt,
                onSelected: (_) => onSelected(opt),
              ))
          .toList(),
    );
  }
}
