import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'category_chips.dart';

class CategoryChipsHeader extends StatelessWidget {
  const CategoryChipsHeader({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String activeCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _CategoryChipsHeaderDelegate(
        categories: categories,
        activeCategory: activeCategory,
        onSelected: onSelected,
      ),
    );
  }
}

class _CategoryChipsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CategoryChipsHeaderDelegate({
    required this.categories,
    required this.activeCategory,
    required this.onSelected,
  });

  static const double _chipsHeight = 40;
  static const double _verticalPadding = 8;

  final List<String> categories;
  final String activeCategory;
  final ValueChanged<String> onSelected;

  @override
  double get minExtent => _chipsHeight + _verticalPadding * 2;

  @override
  double get maxExtent => _chipsHeight + _verticalPadding * 2;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = ShadTheme.of(context);
    return Container(
      color: theme.colorScheme.background,
      padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
      alignment: Alignment.centerLeft,
      child: CategoryChips(
        categories: categories,
        activeCategory: activeCategory,
        onSelected: onSelected,
      ),
    );
  }

  @override
  bool shouldRebuild(_CategoryChipsHeaderDelegate oldDelegate) {
    return categories != oldDelegate.categories ||
        activeCategory != oldDelegate.activeCategory;
  }
}
