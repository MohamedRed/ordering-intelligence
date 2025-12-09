import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/order.dart';
import '../../providers/menu_providers.dart';

class MenuEditorScreen extends ConsumerStatefulWidget {
  const MenuEditorScreen({super.key});

  @override
  ConsumerState<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends ConsumerState<MenuEditorScreen> {
  late Future<List<MenuItemModel>> _future;
  late MenuApi _api;

  @override
  void initState() {
    super.initState();
    _api = MenuApi();
    _future = _api.fetchMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Editor')),
      body: FutureBuilder<List<MenuItemModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          var items = snapshot.data ?? [];
          return MenuEditorList(
            items: items,
            onSave: (newItems) async {
              await _api.saveMenu(newItems);
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Menu saved')));
              }
              setState(() {
                _future = Future.value(newItems);
              });
            },
          );
        },
      ),
    );
  }
}

class MenuItemModel {
  MenuItemModel({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.available,
    required this.category,
    required this.modifiers,
  });
  final String id;
  final String name;
  final int priceCents;
  final bool available;
  final String category;
  final List<MenuModifierModel> modifiers;

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      priceCents: json['priceCents'] ?? 0,
      available: json['available'] ?? true,
      category: json['category'] ?? '',
      modifiers: (json['modifiers'] as List<dynamic>? ?? [])
          .map((e) => MenuModifierModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
        'available': available,
        'category': category,
        'modifiers': modifiers.map((e) => e.toJson()).toList(),
      };

  MenuItemModel copyWith(
      {String? id,
      String? name,
      int? priceCents,
      bool? available,
      String? category,
      List<MenuModifierModel>? modifiers}) {
    return MenuItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      priceCents: priceCents ?? this.priceCents,
      available: available ?? this.available,
      category: category ?? this.category,
      modifiers: modifiers ?? this.modifiers,
    );
  }
}

class MenuModifierModel {
  final String name;
  final int priceCents;

  MenuModifierModel({required this.name, required this.priceCents});

  factory MenuModifierModel.fromJson(Map<String, dynamic> json) =>
      MenuModifierModel(
        name: json['name'] ?? '',
        priceCents: json['priceCents'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceCents': priceCents,
      };
}

class MenuEditorList extends StatefulWidget {
  const MenuEditorList({super.key, required this.items, required this.onSave});
  final List<MenuItemModel> items;
  final Future<void> Function(List<MenuItemModel>) onSave;

  @override
  State<MenuEditorList> createState() => _MenuEditorListState();
}

class _MenuEditorListState extends State<MenuEditorList> {
  late List<MenuItemModel> items;

  @override
  void initState() {
    super.initState();
    items = List.of(widget.items);
  }

  void _addItem() {
    setState(() {
      items = [
        ...items,
        MenuItemModel(
            id: 'item-${DateTime.now().millisecondsSinceEpoch}',
            name: 'New Item',
            priceCents: 0,
            available: true,
            category: '',
            modifiers: const [])
      ];
    });
  }

  void _updateItem(int index, MenuItemModel updated) {
    setState(() {
      items[index] = updated;
    });
  }

  void _removeItem(int index) {
    setState(() {
      items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: item.name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onChanged: (v) =>
                            _updateItem(index, item.copyWith(name: v)),
                      ),
                      TextFormField(
                        initialValue: item.category,
                        decoration: const InputDecoration(
                            labelText: 'Category (optional)'),
                        onChanged: (v) =>
                            _updateItem(index, item.copyWith(category: v)),
                      ),
                      TextFormField(
                        initialValue: item.priceCents.toString(),
                        decoration:
                            const InputDecoration(labelText: 'Price (cents)'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _updateItem(index,
                            item.copyWith(priceCents: int.tryParse(v) ?? 0)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Modifiers',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...item.modifiers.asMap().entries.map((entry) {
                        final modIndex = entry.key;
                        final mod = entry.value;
                        return Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: mod.name,
                                decoration:
                                    const InputDecoration(labelText: 'Name'),
                                onChanged: (v) {
                                  final updated = List<MenuModifierModel>.from(
                                      item.modifiers);
                                  updated[modIndex] = MenuModifierModel(
                                      name: v, priceCents: mod.priceCents);
                                  _updateItem(
                                      index, item.copyWith(modifiers: updated));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: mod.priceCents.toString(),
                                decoration: const InputDecoration(
                                    labelText: 'Price (cents)'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final updated = List<MenuModifierModel>.from(
                                      item.modifiers);
                                  updated[modIndex] = MenuModifierModel(
                                      name: mod.name,
                                      priceCents: int.tryParse(v) ?? 0);
                                  _updateItem(
                                      index, item.copyWith(modifiers: updated));
                                },
                              ),
                            ),
                            IconButton(
                                onPressed: () {
                                  final updated = List<MenuModifierModel>.from(
                                      item.modifiers);
                                  updated.removeAt(modIndex);
                                  _updateItem(
                                      index, item.copyWith(modifiers: updated));
                                },
                                icon: const Icon(Icons.delete_outline))
                          ],
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final updated =
                                List<MenuModifierModel>.from(item.modifiers)
                                  ..add(MenuModifierModel(
                                      name: 'Extra', priceCents: 0));
                            _updateItem(
                                index, item.copyWith(modifiers: updated));
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add modifier'),
                        ),
                      ),
                      SwitchListTile(
                        value: item.available,
                        title: const Text('Available'),
                        onChanged: (v) =>
                            _updateItem(index, item.copyWith(available: v)),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _removeItem(index),
                          child: const Text('Remove'),
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item')),
              ElevatedButton.icon(
                onPressed: () async => widget.onSave(items),
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              )
            ],
          ),
        )
      ],
    );
  }
}
