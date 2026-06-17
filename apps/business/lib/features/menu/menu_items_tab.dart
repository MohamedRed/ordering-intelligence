import 'package:flutter/material.dart';

import '../../models/menu.dart';
import 'menu_item_editor_card.dart';

typedef MenuItemChanged = void Function(int index, MenuItemModel item);
typedef MenuItemRemoved = void Function(int index);

class MenuItemsTab extends StatelessWidget {
  const MenuItemsTab({
    super.key,
    required this.items,
    required this.onItemChanged,
    required this.onItemRemoved,
  });

  final List<MenuItemModel> items;
  final MenuItemChanged onItemChanged;
  final MenuItemRemoved onItemRemoved;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return MenuItemEditorCard(
          index: index,
          item: items[index],
          onChanged: onItemChanged,
          onRemoved: onItemRemoved,
        );
      },
    );
  }
}
