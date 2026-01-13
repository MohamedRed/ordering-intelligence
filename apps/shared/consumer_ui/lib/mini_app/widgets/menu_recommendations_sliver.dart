import 'package:flutter/material.dart';

import 'recommended_orders_section.dart';
import 'package:consumer_core/consumer_core.dart';

class MenuRecommendationsSliver extends StatelessWidget {
  const MenuRecommendationsSliver({
    super.key,
    required this.orders,
    required this.onSelect,
  });

  final List<RecommendedOrder> orders;
  final ValueChanged<RecommendedOrder>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          RecommendedOrdersSection(
            title: 'Past orders in this store',
            orders: orders,
            showStoreName: false,
            inline: true,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}