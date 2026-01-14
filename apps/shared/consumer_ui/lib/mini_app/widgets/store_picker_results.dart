import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'centered_message.dart';
import 'recommended_orders_section.dart';
import 'store_choice_card.dart';
import 'package:consumer_core/consumer_core.dart';

class StorePickerResults extends StatelessWidget {
  const StorePickerResults({
    super.key,
    required this.recommendedOrders,
    required this.searchResults,
    required this.onSelectStore,
    required this.onSelectRecommended,
  });

  final List<RecommendedOrder> recommendedOrders;
  final List<StoreChoice> searchResults;
  final ValueChanged<StoreChoice> onSelectStore;
  final ValueChanged<RecommendedOrder> onSelectRecommended;

  @override
  Widget build(BuildContext context) {
    final singleOrders =
        recommendedOrders.where((order) => !order.isGroupOrder).toList();
    final groupOrders =
        recommendedOrders.where((order) => order.isGroupOrder).toList();
    if (singleOrders.isEmpty && groupOrders.isEmpty && searchResults.isEmpty) {
      return const CenteredMessage(
        title: 'No results yet',
        description: 'Search for a store to begin ordering.',
      );
    }
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
    if (searchResults.isNotEmpty) {
      children.add(const SizedBox(height: 16));
      children.add(
        Text('Search results', style: ShadTheme.of(context).textTheme.large),
      );
      children.add(const SizedBox(height: 8));
      for (final store in searchResults) {
        children.add(StoreChoiceCard(store: store, onTap: () => onSelectStore(store)));
        children.add(const SizedBox(height: 12));
      }
    }
    return ListView(
      children: children,
    );
  }
}
