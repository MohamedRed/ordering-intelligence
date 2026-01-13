import 'package:flutter/material.dart';

import 'category_chips_header.dart';
import 'menu_header.dart';
import 'menu_items_sliver.dart';
import 'menu_recommendations_sliver.dart';
import 'package:consumer_core/consumer_core.dart';

class MenuViewSlivers extends StatelessWidget {
  const MenuViewSlivers({
    super.key,
    required this.storeName,
    this.showHeader = true,
    required this.categories,
    required this.activeCategory,
    required this.items,
    required this.recommendations,
    this.identityPanel,
    required this.groupOrderPanel,
    required this.onChangeStore,
    required this.onCategorySelected,
    required this.onAddItem,
    required this.onSelectRecommendation,
    required this.formatPrice,
    required this.bottomPadding,
    required this.extraScrollPadding,
    this.scrollController,
    this.itemsAnchorKey,
  });

  final String storeName;
  final bool showHeader;
  final List<String> categories;
  final String activeCategory;
  final List<MenuItem> items;
  final List<RecommendedOrder> recommendations;
  final Widget? identityPanel;
  final Widget? groupOrderPanel;
  final VoidCallback onChangeStore;
  final ValueChanged<String> onCategorySelected;
  final void Function(MenuItem item) onAddItem;
  final ValueChanged<RecommendedOrder>? onSelectRecommendation;
  final String Function(int) formatPrice;
  final double bottomPadding;
  final double extraScrollPadding;
  final ScrollController? scrollController;
  final GlobalKey? itemsAnchorKey;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        if (showHeader)
          SliverToBoxAdapter(
            child: MenuHeader(
              storeName: storeName,
              onChangeStore: onChangeStore,
            ),
          ),
        if (identityPanel != null) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(child: identityPanel!),
        ],
        if (groupOrderPanel != null) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(child: groupOrderPanel!),
        ],
        MenuRecommendationsSliver(
          orders: recommendations,
          onSelect: onSelectRecommendation,
        ),
        if (categories.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          CategoryChipsHeader(
            categories: categories,
            activeCategory: activeCategory,
            onSelected: onCategorySelected,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ] else ...[
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        SliverToBoxAdapter(
          child: SizedBox(key: itemsAnchorKey, height: 0),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          sliver: MenuItemsSliver(
            items: items,
            onAddItem: onAddItem,
            formatPrice: formatPrice,
          ),
        ),
        if (items.length < 6)
          SliverToBoxAdapter(child: SizedBox(height: extraScrollPadding)),
      ],
    );
  }
}