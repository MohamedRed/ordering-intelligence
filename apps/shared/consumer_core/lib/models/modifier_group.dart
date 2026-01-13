import 'modifier_option.dart';

class ModifierGroup {
  final String id;
  final String name;
  final bool required;
  final int minSelections;
  final int maxSelections;
  final List<ModifierOption> options;

  const ModifierGroup({
    required this.id,
    required this.name,
    required this.required,
    required this.minSelections,
    required this.maxSelections,
    required this.options,
  });

  factory ModifierGroup.fromJson(Map<String, dynamic> json) {
    final optionsJson = json['options'];
    final parsedOptions = <ModifierOption>[];
    if (optionsJson is List) {
      for (final option in optionsJson) {
        if (option is Map<String, dynamic>) {
          parsedOptions.add(ModifierOption.fromJson(option));
        }
      }
    }
    return ModifierGroup(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      required: json['required'] == true,
      minSelections: (json['minSelections'] ?? 0) is int
          ? json['minSelections'] as int
          : int.tryParse((json['minSelections'] ?? '0').toString()) ?? 0,
      maxSelections: (json['maxSelections'] ?? 0) is int
          ? json['maxSelections'] as int
          : int.tryParse((json['maxSelections'] ?? '0').toString()) ?? 0,
      options: parsedOptions,
    );
  }
}
