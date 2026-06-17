import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_editor_factories.dart';
import 'menu_modifier_groups_editor.dart';

class MenuItemEditorCard extends StatelessWidget {
  const MenuItemEditorCard({
    super.key,
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onRemoved,
  });

  final int index;
  final MenuItemModel item;
  final void Function(int index, MenuItemModel item) onChanged;
  final void Function(int index) onRemoved;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShadInputFormField(
            initialValue: item.name,
            label: const Text('Name'),
            onChanged: (value) => _update(item.copyWith(name: value)),
          ),
          const SizedBox(height: 10),
          ShadInputFormField(
            initialValue: item.category,
            label: const Text('Category (optional)'),
            onChanged: (value) => _update(item.copyWith(category: value)),
          ),
          const SizedBox(height: 10),
          ShadInputFormField(
            initialValue: item.priceCents.toString(),
            label: const Text('Price (cents)'),
            keyboardType: TextInputType.number,
            onChanged: (value) =>
                _update(item.copyWith(priceCents: parseMenuEditorInt(value))),
          ),
          const SizedBox(height: 12),
          MenuModifierGroupsEditor(
            item: item,
            onChanged: _update,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Available'),
              const Spacer(),
              ShadSwitch(
                value: item.available,
                onChanged: (value) => _update(item.copyWith(available: value)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.outline(
              onPressed: () => onRemoved(index),
              child: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }

  void _update(MenuItemModel updated) {
    onChanged(index, updated);
  }
}
