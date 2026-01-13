import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import '../../providers/menu_providers.dart';
import '../../widgets/shad_snackbar.dart';

class MenuEditorScreen extends ConsumerStatefulWidget {
  const MenuEditorScreen({super.key});

  @override
  ConsumerState<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends ConsumerState<MenuEditorScreen> {
  late Future<MenuRecordModel> _future;
  late MenuApi _api;

  @override
  void initState() {
    super.initState();
    _api = MenuApi();
    _future = _api.fetchMenu();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MenuRecordModel>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final menu = snapshot.data ?? MenuRecordModel.empty();
        return MenuEditorList(
          menu: menu,
          onSave: (newMenu) async {
            await _api.saveMenu(newMenu);
            if (!context.mounted) return;
            showShadSnack(
              context,
              title: 'Menu saved',
              type: ShadSnackType.success,
            );
            setState(() {
              _future = Future.value(newMenu);
            });
          },
        );
      },
    );
  }
}

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
      menu = menu.copyWith(items: [
        ...menu.items,
        MenuItemModel(
            id: 'item-${DateTime.now().millisecondsSinceEpoch}',
            name: 'New Item',
            priceCents: 0,
            available: true,
            category: '',
            modifiers: const [],
            modifierGroups: const [])
      ]);
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
                      _buildItemsTab(context),
                      _buildBundlesTab(context),
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
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildItemsTab(BuildContext context) {
    final items = menu.items;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return ShadCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShadInputFormField(
                initialValue: item.name,
                label: const Text('Name'),
                onChanged: (v) => _updateItem(index, item.copyWith(name: v)),
              ),
              const SizedBox(height: 10),
              ShadInputFormField(
                initialValue: item.category,
                label: const Text('Category (optional)'),
                onChanged: (v) => _updateItem(index, item.copyWith(category: v)),
              ),
              const SizedBox(height: 10),
              ShadInputFormField(
                initialValue: item.priceCents.toString(),
                label: const Text('Price (cents)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _updateItem(index, item.copyWith(priceCents: int.tryParse(v) ?? 0)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Modifier groups', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  ShadButton.ghost(
                    onPressed: () {
                      final groups = List<MenuModifierGroupModel>.from(item.modifierGroups)
                        ..add(
                          MenuModifierGroupModel(
                            id: 'group-${DateTime.now().millisecondsSinceEpoch}',
                            name: 'Group',
                            required: false,
                            minSelections: 0,
                            maxSelections: 0,
                            options: const [],
                          ),
                        );
                      _updateItem(index, item.copyWith(modifierGroups: groups));
                    },
                    child: const Text('Add group'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...item.modifierGroups.asMap().entries.map((entry) {
                final gIndex = entry.key;
                final group = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ShadCard(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ShadInputFormField(
                                initialValue: group.name,
                                label: const Text('Group name'),
                                onChanged: (v) {
                                  final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                  groups[gIndex] = group.copyWith(name: v);
                                  _updateItem(index, item.copyWith(modifierGroups: groups));
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                final groups = List<MenuModifierGroupModel>.from(item.modifierGroups)..removeAt(gIndex);
                                _updateItem(index, item.copyWith(modifierGroups: groups));
                              },
                              icon: const Icon(Icons.delete_outline),
                            )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Required'),
                            const SizedBox(width: 8),
                            ShadSwitch(
                              value: group.required,
                              onChanged: (v) {
                                final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                groups[gIndex] = group.copyWith(required: v, minSelections: v && group.minSelections == 0 ? 1 : group.minSelections);
                                _updateItem(index, item.copyWith(modifierGroups: groups));
                              },
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 120,
                              child: ShadInputFormField(
                                initialValue: group.minSelections.toString(),
                                label: const Text('Min'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                  groups[gIndex] = group.copyWith(minSelections: int.tryParse(v) ?? 0);
                                  _updateItem(index, item.copyWith(modifierGroups: groups));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: ShadInputFormField(
                                initialValue: group.maxSelections.toString(),
                                label: const Text('Max'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                  groups[gIndex] = group.copyWith(maxSelections: int.tryParse(v) ?? 0);
                                  _updateItem(index, item.copyWith(modifierGroups: groups));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('Options', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        ...group.options.asMap().entries.map((optEntry) {
                          final oIndex = optEntry.key;
                          final opt = optEntry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ShadInputFormField(
                                    initialValue: opt.name,
                                    label: const Text('Name'),
                                    onChanged: (v) {
                                      final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                      final options = List<MenuModifierOptionModel>.from(group.options);
                                      options[oIndex] = MenuModifierOptionModel(id: opt.id, name: v, priceCents: opt.priceCents);
                                      groups[gIndex] = group.copyWith(options: options);
                                      _updateItem(index, item.copyWith(modifierGroups: groups));
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 140,
                                  child: ShadInputFormField(
                                    initialValue: opt.priceCents.toString(),
                                    label: const Text('Price (cents)'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                      final options = List<MenuModifierOptionModel>.from(group.options);
                                      options[oIndex] = MenuModifierOptionModel(id: opt.id, name: opt.name, priceCents: int.tryParse(v) ?? 0);
                                      groups[gIndex] = group.copyWith(options: options);
                                      _updateItem(index, item.copyWith(modifierGroups: groups));
                                    },
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                                    final options = List<MenuModifierOptionModel>.from(group.options)..removeAt(oIndex);
                                    groups[gIndex] = group.copyWith(options: options);
                                    _updateItem(index, item.copyWith(modifierGroups: groups));
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                )
                              ],
                            ),
                          );
                        }),
                        ShadButton.ghost(
                          onPressed: () {
                            final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
                            final options = List<MenuModifierOptionModel>.from(group.options)
                              ..add(MenuModifierOptionModel(
                                id: 'opt-${DateTime.now().millisecondsSinceEpoch}',
                                name: 'Option',
                                priceCents: 0,
                              ));
                            groups[gIndex] = group.copyWith(options: options);
                            _updateItem(index, item.copyWith(modifierGroups: groups));
                          },
                          child: const Text('Add option'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Available'),
                  const Spacer(),
                  ShadSwitch(
                    value: item.available,
                    onChanged: (v) => _updateItem(index, item.copyWith(available: v)),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: ShadButton.outline(
                  onPressed: () => _removeItem(index),
                  child: const Text('Remove'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildBundlesTab(BuildContext context) {
    final rules = menu.bundleRules;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ShadButton.outline(
          onPressed: () {
            final updated = List<BundleRuleModel>.from(rules)
              ..add(
                BundleRuleModel(
                  bundleId: 'bundle-${DateTime.now().millisecondsSinceEpoch}',
                  displayName: 'Bundle',
                  triggerItemId: '',
                  triggerCategory: '',
                  components: const [],
                  promptHintsFr: '',
                ),
              );
            setState(() {
              menu = menu.copyWith(bundleRules: updated);
            });
          },
          child: const Text('Add bundle rule'),
        ),
        const SizedBox(height: 12),
        ...rules.asMap().entries.map((entry) {
          final rIndex = entry.key;
          final rule = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShadCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ShadInputFormField(
                          initialValue: rule.displayName,
                          label: const Text('Display name'),
                          onChanged: (v) {
                            final updated = List<BundleRuleModel>.from(rules);
                            updated[rIndex] = rule.copyWith(displayName: v);
                            setState(() => menu = menu.copyWith(bundleRules: updated));
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final updated = List<BundleRuleModel>.from(rules)..removeAt(rIndex);
                          setState(() => menu = menu.copyWith(bundleRules: updated));
                        },
                        icon: const Icon(Icons.delete_outline),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  ShadInputFormField(
                    initialValue: rule.bundleId,
                    label: const Text('Bundle ID'),
                    onChanged: (v) {
                      final updated = List<BundleRuleModel>.from(rules);
                      updated[rIndex] = rule.copyWith(bundleId: v);
                      setState(() => menu = menu.copyWith(bundleRules: updated));
                    },
                  ),
                  const SizedBox(height: 8),
                  ShadInputFormField(
                    initialValue: rule.triggerItemId,
                    label: const Text('Trigger item ID (optional)'),
                    onChanged: (v) {
                      final updated = List<BundleRuleModel>.from(rules);
                      updated[rIndex] = rule.copyWith(triggerItemId: v);
                      setState(() => menu = menu.copyWith(bundleRules: updated));
                    },
                  ),
                  const SizedBox(height: 8),
                  ShadInputFormField(
                    initialValue: rule.triggerCategory,
                    label: const Text('Trigger category (optional)'),
                    onChanged: (v) {
                      final updated = List<BundleRuleModel>.from(rules);
                      updated[rIndex] = rule.copyWith(triggerCategory: v);
                      setState(() => menu = menu.copyWith(bundleRules: updated));
                    },
                  ),
                  const SizedBox(height: 8),
                  ShadInputFormField(
                    initialValue: rule.promptHintsFr,
                    label: const Text('Prompt hints FR (optional)'),
                    onChanged: (v) {
                      final updated = List<BundleRuleModel>.from(rules);
                      updated[rIndex] = rule.copyWith(promptHintsFr: v);
                      setState(() => menu = menu.copyWith(bundleRules: updated));
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('Components', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      ShadButton.ghost(
                        onPressed: () {
                          final updated = List<BundleRuleModel>.from(rules);
                          final comps = List<BundleComponentModel>.from(rule.components)
                            ..add(BundleComponentModel(role: '', itemIdsCsv: '', category: '', requiredGroupIdsCsv: ''));
                          updated[rIndex] = rule.copyWith(components: comps);
                          setState(() => menu = menu.copyWith(bundleRules: updated));
                        },
                        child: const Text('Add component'),
                      )
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...rule.components.asMap().entries.map((cEntry) {
                    final cIndex = cEntry.key;
                    final comp = cEntry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ShadCard(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ShadInputFormField(
                                    initialValue: comp.role,
                                    label: const Text('Role (drink/side/...)'),
                                    onChanged: (v) {
                                      final updated = List<BundleRuleModel>.from(rules);
                                      final comps = List<BundleComponentModel>.from(rule.components);
                                      comps[cIndex] = comp.copyWith(role: v);
                                      updated[rIndex] = rule.copyWith(components: comps);
                                      setState(() => menu = menu.copyWith(bundleRules: updated));
                                    },
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    final updated = List<BundleRuleModel>.from(rules);
                                    final comps = List<BundleComponentModel>.from(rule.components)..removeAt(cIndex);
                                    updated[rIndex] = rule.copyWith(components: comps);
                                    setState(() => menu = menu.copyWith(bundleRules: updated));
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ShadInputFormField(
                              initialValue: comp.category,
                              label: const Text('Allowed category (optional)'),
                              onChanged: (v) {
                                final updated = List<BundleRuleModel>.from(rules);
                                final comps = List<BundleComponentModel>.from(rule.components);
                                comps[cIndex] = comp.copyWith(category: v);
                                updated[rIndex] = rule.copyWith(components: comps);
                                setState(() => menu = menu.copyWith(bundleRules: updated));
                              },
                            ),
                            const SizedBox(height: 8),
                            ShadInputFormField(
                              initialValue: comp.itemIdsCsv,
                              label: const Text('Allowed item IDs (csv, optional)'),
                              onChanged: (v) {
                                final updated = List<BundleRuleModel>.from(rules);
                                final comps = List<BundleComponentModel>.from(rule.components);
                                comps[cIndex] = comp.copyWith(itemIdsCsv: v);
                                updated[rIndex] = rule.copyWith(components: comps);
                                setState(() => menu = menu.copyWith(bundleRules: updated));
                              },
                            ),
                            const SizedBox(height: 8),
                            ShadInputFormField(
                              initialValue: comp.requiredGroupIdsCsv,
                              label: const Text('Required group IDs (csv, optional)'),
                              onChanged: (v) {
                                final updated = List<BundleRuleModel>.from(rules);
                                final comps = List<BundleComponentModel>.from(rule.components);
                                comps[cIndex] = comp.copyWith(requiredGroupIdsCsv: v);
                                updated[rIndex] = rule.copyWith(components: comps);
                                setState(() => menu = menu.copyWith(bundleRules: updated));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
