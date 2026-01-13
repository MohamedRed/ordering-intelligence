

import 'package:consumer_core/consumer_core.dart';

String selectionHint(ModifierGroup group) {
  if (group.maxSelections > 0) {
    return 'Required: choose ${group.minSelections} - ${group.maxSelections}';
  }
  if (group.minSelections > 0) {
    return 'Required: choose at least ${group.minSelections}';
  }
  return 'Optional';
}

String? validateSelections(
  MenuItem item,
  Map<String, Set<String>> selections,
) {
  for (final group in item.modifierGroups) {
    final selected = selections[group.id]?.length ?? 0;
    if (group.minSelections > 0 && selected < group.minSelections) {
      return 'Select at least ${group.minSelections} in ${group.name}.';
    }
    if (group.maxSelections > 0 && selected > group.maxSelections) {
      return 'Select at most ${group.maxSelections} in ${group.name}.';
    }
  }
  return null;
}

List<ModifierSelection> buildSelections(
  MenuItem item,
  Map<String, Set<String>> selections,
) {
  final result = <ModifierSelection>[];
  for (final group in item.modifierGroups) {
    final selected = selections[group.id] ?? <String>{};
    for (final option in group.options) {
      if (selected.contains(option.id)) {
        result.add(
          ModifierSelection(
            groupId: group.id,
            optionId: option.id,
            name: option.name,
            priceCents: option.priceCents,
          ),
        );
      }
    }
  }
  return result;
}