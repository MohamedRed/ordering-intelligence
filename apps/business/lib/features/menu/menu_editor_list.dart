import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_bundles_tab.dart';
import 'menu_editor_factories.dart';
import 'menu_items_tab.dart';

class MenuEditorList extends StatefulWidget {
  const MenuEditorList({super.key, required this.menu, required this.onSave});

  final MenuRecordModel menu;
  final Future<void> Function(MenuRecordModel) onSave;

  @override
  State<MenuEditorList> createState() => _MenuEditorListState();
}

class _MenuEditorListState extends State<MenuEditorList> {
  late MenuRecordModel menu;

  @override
  void initState() {
    super.initState();
    menu = widget.menu;
  }

  void _addItem() {
    setState(() {
      menu = menu.copyWith(
        items: [...menu.items, newMenuEditorItem(DateTime.now())],
      );
    });
  }

  void _updateItem(int index, MenuItemModel updated) {
    setState(() {
      final items = List<MenuItemModel>.from(menu.items);
      items[index] = updated;
      menu = menu.copyWith(items: items);
    });
  }

  void _removeItem(int index) {
    setState(() {
      final items = List<MenuItemModel>.from(menu.items)..removeAt(index);
      menu = menu.copyWith(items: items);
    });
  }

  void _updateBundleRules(List<BundleRuleModel> rules) {
    setState(() => menu = menu.copyWith(bundleRules: rules));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Items'),
                    Tab(text: 'Bundles'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      MenuItemsTab(
                        items: menu.items,
                        onItemChanged: _updateItem,
                        onItemRemoved: _removeItem,
                      ),
                      MenuBundlesTab(
                        rules: menu.bundleRules,
                        onRulesChanged: _updateBundleRules,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ShadButton.outline(
                onPressed: _addItem,
                child: const Text('Add Item'),
              ),
              const Spacer(),
              ShadButton(
                onPressed: () async => widget.onSave(menu),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
