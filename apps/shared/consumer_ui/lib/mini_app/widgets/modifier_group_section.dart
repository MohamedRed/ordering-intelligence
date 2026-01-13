import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_core/consumer_core.dart';

class ModifierGroupSection extends StatelessWidget {
  const ModifierGroupSection({
    super.key,
    required this.group,
    required this.selectedIds,
    required this.selectionHint,
    required this.onToggle,
  });

  final ModifierGroup group;
  final Set<String> selectedIds;
  final String selectionHint;
  final void Function(String optionId) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.name, style: ShadTheme.of(context).textTheme.large),
        const SizedBox(height: 4),
        Text(selectionHint, style: ShadTheme.of(context).textTheme.muted),
        const SizedBox(height: 8),
        for (final option in group.options)
          CheckboxListTile(
            dense: true,
            value: selectedIds.contains(option.id),
            onChanged: (_) => onToggle(option.id),
            title: Text(option.name),
            subtitle: option.priceCents > 0
                ? Text('+ \$${(option.priceCents / 100).toStringAsFixed(2)}')
                : null,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}