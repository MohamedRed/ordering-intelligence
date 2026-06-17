import 'menu_modifier.dart';

class MenuItemModel {
  MenuItemModel({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.available,
    required this.category,
    required this.modifiers,
    required this.modifierGroups,
  });

  final String id;
  final String name;
  final int priceCents;
  final bool available;
  final String category;
  final List<MenuModifierModel> modifiers;
  final List<MenuModifierGroupModel> modifierGroups;

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    final legacyModifiers = (json['modifiers'] as List<dynamic>? ?? [])
        .map((entry) =>
            MenuModifierModel.fromJson(entry as Map<String, dynamic>))
        .toList();
    final groups = (json['modifierGroups'] as List<dynamic>? ?? [])
        .map((entry) =>
            MenuModifierGroupModel.fromJson(entry as Map<String, dynamic>))
        .toList();
    return MenuItemModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      priceCents: json['priceCents'] ?? 0,
      available: json['available'] ?? true,
      category: json['category'] ?? '',
      modifiers: legacyModifiers,
      modifierGroups:
          groups.isNotEmpty ? groups : deriveLegacyGroup(legacyModifiers),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
        'available': available,
        'category': category,
        'modifierGroups':
            modifierGroups.map((group) => group.toJson()).toList(),
        'modifiers': modifiers.map((modifier) => modifier.toJson()).toList(),
      };

  MenuItemModel copyWith({
    String? id,
    String? name,
    int? priceCents,
    bool? available,
    String? category,
    List<MenuModifierModel>? modifiers,
    List<MenuModifierGroupModel>? modifierGroups,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      name: name ?? this.name,
      priceCents: priceCents ?? this.priceCents,
      available: available ?? this.available,
      category: category ?? this.category,
      modifiers: modifiers ?? this.modifiers,
      modifierGroups: modifierGroups ?? this.modifierGroups,
    );
  }
}
