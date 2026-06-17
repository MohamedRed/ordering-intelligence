class MenuModifierModel {
  MenuModifierModel({required this.name, required this.priceCents});

  final String name;
  final int priceCents;

  factory MenuModifierModel.fromJson(Map<String, dynamic> json) {
    return MenuModifierModel(
      name: json['name'] ?? '',
      priceCents: json['priceCents'] ?? 0,
    );
  }

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
          .map((entry) =>
              MenuModifierOptionModel.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'required': required,
        'minSelections': minSelections,
        'maxSelections': maxSelections,
        'options': options.map((option) => option.toJson()).toList(),
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
  MenuModifierOptionModel({
    required this.id,
    required this.name,
    required this.priceCents,
  });

  final String id;
  final String name;
  final int priceCents;

  factory MenuModifierOptionModel.fromJson(Map<String, dynamic> json) {
    return MenuModifierOptionModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      priceCents: json['priceCents'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
      };
}

List<MenuModifierGroupModel> deriveLegacyGroup(
  List<MenuModifierModel> legacy,
) {
  if (legacy.isEmpty) return const [];
  return [
    MenuModifierGroupModel(
      id: 'legacy_modifiers',
      name: 'Options',
      required: false,
      minSelections: 0,
      maxSelections: legacy.length,
      options: legacy
          .map(
            (modifier) => MenuModifierOptionModel(
              id: safeId(modifier.name),
              name: modifier.name,
              priceCents: modifier.priceCents,
            ),
          )
          .toList(),
    ),
  ];
}

String safeId(String input) {
  final normalized = input.toLowerCase().trim();
  final slug = normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isNotEmpty ? slug : 'id';
}
