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
    if (recommendedOrders.isEmpty && searchResults.isEmpty) {
      return const CenteredMessage(
        title: 'No results yet',
        description: 'Search for a restaurant to begin ordering.',
      );
    }
    final children = <Widget>[];
    if (recommendedOrders.isNotEmpty) {
      children.add(
        RecommendedOrdersSection(
          title: 'Recommended from past orders',
          orders: recommendedOrders,
          onSelect: onSelectRecommended,
        ),
      );
    }
    if (searchResults.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
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