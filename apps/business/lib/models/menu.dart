class MenuRecordModel {
  MenuRecordModel({required this.items, required this.bundleRules});
  final List<MenuItemModel> items;
  final List<BundleRuleModel> bundleRules;

  factory MenuRecordModel.empty() => MenuRecordModel(items: const [], bundleRules: const []);

  factory MenuRecordModel.fromJson(Map<String, dynamic> json) {
    return MenuRecordModel(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      bundleRules: (json['bundleRules'] as List<dynamic>? ?? [])
          .map((e) => BundleRuleModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'bundleRules': bundleRules.map((e) => e.toJson()).toList(),
      };

  MenuRecordModel copyWith({List<MenuItemModel>? items, List<BundleRuleModel>? bundleRules}) {
    return MenuRecordModel(
      items: items ?? this.items,
      bundleRules: bundleRules ?? this.bundleRules,
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
        .map((e) => MenuModifierModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final groups = (json['modifierGroups'] as List<dynamic>? ?? [])
        .map((e) => MenuModifierGroupModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final effectiveGroups = groups.isNotEmpty ? groups : deriveLegacyGroup(legacyModifiers);
    return MenuItemModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      priceCents: json['priceCents'] ?? 0,
      available: json['available'] ?? true,
      category: json['category'] ?? '',
      modifiers: legacyModifiers,
      modifierGroups: effectiveGroups,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
        'available': available,
        'category': category,
        // Prefer structured modifier groups for validation / voice agents.
        'modifierGroups': modifierGroups.map((e) => e.toJson()).toList(),
        // Keep legacy field present for backward compatibility; can be empty.
        'modifiers': modifiers.map((e) => e.toJson()).toList(),
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

class MenuModifierModel {
  final String name;
  final int priceCents;

  MenuModifierModel({required this.name, required this.priceCents});

  factory MenuModifierModel.fromJson(Map<String, dynamic> json) => MenuModifierModel(
        name: json['name'] ?? '',
        priceCents: json['priceCents'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceCents': priceCents,
      };
}

class MenuModifierGroupModel {
  MenuModifierGroupModel({
    required this.id,
    required this.name,
    required this.required,
    required this.minSelections,
    required this.maxSelections,
    required this.options,
  });

  final String id;
  final String name;
  final bool required;
  final int minSelections;
  final int maxSelections;
  final List<MenuModifierOptionModel> options;

  factory MenuModifierGroupModel.fromJson(Map<String, dynamic> json) {
    return MenuModifierGroupModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      required: json['required'] ?? false,
      minSelections: json['minSelections'] ?? 0,
      maxSelections: json['maxSelections'] ?? 0,
      options: (json['options'] as List<dynamic>? ?? [])
          .map((e) => MenuModifierOptionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'required': required,
        'minSelections': minSelections,
        'maxSelections': maxSelections,
        'options': options.map((e) => e.toJson()).toList(),
      };

  MenuModifierGroupModel copyWith({
    String? id,
    String? name,
    bool? required,
    int? minSelections,
    int? maxSelections,
    List<MenuModifierOptionModel>? options,
  }) {
    return MenuModifierGroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      required: required ?? this.required,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      options: options ?? this.options,
    );
  }
}

class MenuModifierOptionModel {
  MenuModifierOptionModel({required this.id, required this.name, required this.priceCents});
  final String id;
  final String name;
  final int priceCents;

  factory MenuModifierOptionModel.fromJson(Map<String, dynamic> json) => MenuModifierOptionModel(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        priceCents: json['priceCents'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
      };
}

class BundleRuleModel {
  BundleRuleModel({
    required this.bundleId,
    required this.displayName,
    required this.triggerItemId,
    required this.triggerCategory,
    required this.components,
    required this.promptHintsFr,
  });

  final String bundleId;
  final String displayName;
  final String triggerItemId;
  final String triggerCategory;
  final List<BundleComponentModel> components;
  final String promptHintsFr;

  factory BundleRuleModel.fromJson(Map<String, dynamic> json) => BundleRuleModel(
        bundleId: json['bundleId'] ?? '',
        displayName: json['displayName'] ?? '',
        triggerItemId: json['triggerItemId'] ?? '',
        triggerCategory: json['triggerCategory'] ?? '',
        components: (json['components'] as List<dynamic>? ?? [])
            .map((e) => BundleComponentModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        promptHintsFr: json['promptHintsFr'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'bundleId': bundleId,
        'displayName': displayName,
        if (triggerItemId.isNotEmpty) 'triggerItemId': triggerItemId,
        if (triggerCategory.isNotEmpty) 'triggerCategory': triggerCategory,
        'components': components.map((e) => e.toJson()).toList(),
        if (promptHintsFr.isNotEmpty) 'promptHintsFr': promptHintsFr,
      };

  BundleRuleModel copyWith({
    String? bundleId,
    String? displayName,
    String? triggerItemId,
    String? triggerCategory,
    List<BundleComponentModel>? components,
    String? promptHintsFr,
  }) {
    return BundleRuleModel(
      bundleId: bundleId ?? this.bundleId,
      displayName: displayName ?? this.displayName,
      triggerItemId: triggerItemId ?? this.triggerItemId,
      triggerCategory: triggerCategory ?? this.triggerCategory,
      components: components ?? this.components,
      promptHintsFr: promptHintsFr ?? this.promptHintsFr,
    );
  }
}

class BundleComponentModel {
  BundleComponentModel({
    required this.role,
    required this.itemIdsCsv,
    required this.category,
    required this.requiredGroupIdsCsv,
  });

  final String role;
  final String itemIdsCsv;
  final String category;
  final String requiredGroupIdsCsv;

  factory BundleComponentModel.fromJson(Map<String, dynamic> json) {
    final itemIds = (json['itemIds'] as List<dynamic>? ?? []).cast<String>();
    final groupIds = (json['requiredGroupIds'] as List<dynamic>? ?? []).cast<String>();
    return BundleComponentModel(
      role: json['role'] ?? '',
      itemIdsCsv: itemIds.join(','),
      category: json['category'] ?? '',
      requiredGroupIdsCsv: groupIds.join(','),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        if (splitCsv(itemIdsCsv).isNotEmpty) 'itemIds': splitCsv(itemIdsCsv),
        if (category.isNotEmpty) 'category': category,
        if (splitCsv(requiredGroupIdsCsv).isNotEmpty) 'requiredGroupIds': splitCsv(requiredGroupIdsCsv),
      };

  BundleComponentModel copyWith({
    String? role,
    String? itemIdsCsv,
    String? category,
    String? requiredGroupIdsCsv,
  }) {
    return BundleComponentModel(
      role: role ?? this.role,
      itemIdsCsv: itemIdsCsv ?? this.itemIdsCsv,
      category: category ?? this.category,
      requiredGroupIdsCsv: requiredGroupIdsCsv ?? this.requiredGroupIdsCsv,
    );
  }
}

List<MenuModifierGroupModel> deriveLegacyGroup(List<MenuModifierModel> legacy) {
  if (legacy.isEmpty) return const [];
  return [
    MenuModifierGroupModel(
      id: 'legacy_modifiers',
      name: 'Options',
      required: false,
      minSelections: 0,
      maxSelections: legacy.length,
      options: legacy
          .map((m) => MenuModifierOptionModel(id: safeId(m.name), name: m.name, priceCents: m.priceCents))
          .toList(),
    )
  ];
}

String safeId(String input) {
  final s = input.toLowerCase().trim();
  final out = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return out.isNotEmpty ? out : 'id';
}

List<String> splitCsv(String v) {
  return v
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

