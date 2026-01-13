import 'package:flutter/material.dart';

import '../../models/order.dart';
import 'fuel_order_completion_card.dart';
import 'fuel_order_summary_card.dart';

class FuelOrderSection extends StatelessWidget {
  const FuelOrderSection({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.fuel == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FuelOrderSummaryCard(order: order),
        const SizedBox(height: 12),
        FuelOrderCompletionCard(order: order),
      ],
    );
  }
}
