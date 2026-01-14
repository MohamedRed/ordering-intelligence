import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'centered_message.dart';
import 'recommended_orders_section.dart';
import 'package:consumer_core/consumer_core.dart';

class StorePickerResults extends StatelessWidget {
  const StorePickerResults({
    super.key,
    required this.recommendedOrders,
    required this.onSelectRecommended,
  });

  final List<RecommendedOrder> recommendedOrders;
  final ValueChanged<RecommendedOrder> onSelectRecommended;

  @override
  Widget build(BuildContext context) {
    final singleOrders =
        recommendedOrders.where((order) => !order.isGroupOrder).toList();
    final groupOrders =
        recommendedOrders.where((order) => order.isGroupOrder).toList();
    final children = <Widget>[];
    children.add(
      RecommendedOrdersSection(
        title: 'Recent single orders',
        orders: singleOrders,
        onSelect: onSelectRecommended,
        inline: true,
        emptyLabel: 'No recent single orders yet.',
      ),
    );
    children.add(const SizedBox(height: 12));
    children.add(
      RecommendedOrdersSection(
        title: 'Recent group orders',
        orders: groupOrders,
        onSelect: onSelectRecommended,
        inline: true,
        emptyLabel: 'No group orders yet.',
      ),
    );
    if (singleOrders.isEmpty && groupOrders.isEmpty) {
      children.add(const SizedBox(height: 16));
      children.add(const CenteredMessage(
        title: 'No results yet',
        description: 'Use chat search to find a store.',
      ));
    }
    return ListView(
      children: children,
    );
  }
}
