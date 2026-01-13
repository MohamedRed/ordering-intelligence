import 'package:flutter/material.dart';

import 'centered_message.dart';
import 'menu_item_card.dart';
import 'package:consumer_core/consumer_core.dart';

class MenuItemsSliver extends StatelessWidget {
  const MenuItemsSliver({
    super.key,
    required this.items,
    required this.onAddItem,
    required this.formatPrice,
  });

  final List<MenuItem> items;
  final void Function(MenuItem item) onAddItem;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 24),
          child: CenteredMessage(
            title: 'Nothing to show',
            description: 'Try another category or store.',
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: MenuItemCard(
              item: item,
              onAdd: () => onAddItem(item),
              formatPrice: formatPrice,
            ),
          );
        },
        childCount: items.length,
      ),
    );
  }
}