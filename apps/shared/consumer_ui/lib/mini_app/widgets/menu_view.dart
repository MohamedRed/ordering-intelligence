import 'package:flutter/material.dart';

import 'cart_bar.dart';
import 'menu_view_slivers.dart';
import 'package:consumer_core/consumer_core.dart';

class MenuView extends StatelessWidget {
  const MenuView({
    super.key,
    required this.storeName,
    this.showHeader = true,
    required this.categories,
    required this.activeCategory,
    required this.items,
    required this.recommendations,
    this.identityPanel,
    this.groupOrderPanel,
    required this.onChangeStore,
    required this.onCategorySelected,
    required this.onAddItem,
    this.onSelectRecommendation,
    required this.cartItemCount,
    required this.cartTotalLabel,
    required this.onOpenCart,
    required this.formatPrice,
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
  final int cartItemCount;
  final String cartTotalLabel;
  final VoidCallback onOpenCart;
  final String Function(int) formatPrice;
  final ScrollController? scrollController;
  final GlobalKey? itemsAnchorKey;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = cartItemCount == 0 ? 0.0 : 76.0;
    final extraScrollPadding = MediaQuery.of(context).size.height * 0.35;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          MenuViewSlivers(
            storeName: storeName,
            showHeader: showHeader,
            categories: categories,
            activeCategory: activeCategory,
            items: items,
            recommendations: recommendations,
            identityPanel: identityPanel,
            groupOrderPanel: groupOrderPanel,
            onChangeStore: onChangeStore,
            onCategorySelected: onCategorySelected,
            onAddItem: onAddItem,
            onSelectRecommendation: onSelectRecommendation,
            formatPrice: formatPrice,
            bottomPadding: bottomPadding,
            extraScrollPadding: extraScrollPadding,
            scrollController: scrollController,
            itemsAnchorKey: itemsAnchorKey,
          ),
          if (cartItemCount > 0)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CartBar(
                  itemCount: cartItemCount,
                  totalLabel: cartTotalLabel,
                  onTap: onOpenCart,
                ),
              ),
            ),
        ],
      ),
    );
  }
}