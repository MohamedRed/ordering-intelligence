import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'modifier_dialog_helpers.dart';
import 'modifier_group_section.dart';
import 'package:consumer_core/consumer_core.dart';

class ModifierDialog extends StatefulWidget {
  const ModifierDialog({super.key, required this.item});

  final MenuItem item;

  @override
  State<ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<ModifierDialog> {
  final Map<String, Set<String>> _selections = {};
  String? _error;

  void _toggleSelection(String groupId, String optionId) {
    final current = _selections[groupId] ?? <String>{};
    if (current.contains(optionId)) {
      current.remove(optionId);
    } else {
      current.add(optionId);
    }
    setState(() => _selections[groupId] = current);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Customize ${widget.item.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in widget.item.modifierGroups)
                ModifierGroupSection(
                  group: group,
                  selectedIds: _selections[group.id] ?? const <String>{},
                  selectionHint: group.required || group.minSelections > 0
                      ? selectionHint(group)
                      : 'Optional',
                  onToggle: (optionId) => _toggleSelection(group.id, optionId),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        ShadButton.outline(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ShadButton(
          onPressed: () {
            setState(() => _error = null);
            final error = validateSelections(widget.item, _selections);
            if (error != null) {
              setState(() => _error = error);
              return;
            }
            Navigator.pop(context, buildSelections(widget.item, _selections));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}