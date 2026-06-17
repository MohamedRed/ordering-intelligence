import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_editor_factories.dart';
import 'menu_modifier_option_row.dart';

class MenuModifierGroupsEditor extends StatelessWidget {
  const MenuModifierGroupsEditor({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final MenuItemModel item;
  final ValueChanged<MenuItemModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Modifier groups',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            ShadButton.ghost(
              onPressed: _addGroup,
              child: const Text('Add group'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final entry in item.modifierGroups.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ModifierGroupCard(
              item: item,
              groupIndex: entry.key,
              group: entry.value,
              onChanged: onChanged,
            ),
          ),
      ],
    );
  }

  void _addGroup() {
    final groups = List<MenuModifierGroupModel>.from(item.modifierGroups)
      ..add(newMenuModifierGroup(DateTime.now()));
    onChanged(item.copyWith(modifierGroups: groups));
  }
}

class _ModifierGroupCard extends StatelessWidget {
  const _ModifierGroupCard({
    required this.item,
    required this.groupIndex,
    required this.group,
    required this.onChanged,
  });

  final MenuItemModel item;
  final int groupIndex;
  final MenuModifierGroupModel group;
  final ValueChanged<MenuItemModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
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
                  onChanged: (value) =>
                      _replaceGroup(group.copyWith(name: value)),
                ),
              ),
              IconButton(
                onPressed: _removeGroup,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Required'),
              ShadSwitch(
                value: group.required,
                onChanged: (value) => _replaceGroup(
                  group.copyWith(
                    required: value,
                    minSelections: value && group.minSelections == 0
                        ? 1
                        : group.minSelections,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: ShadInputFormField(
                  initialValue: group.minSelections.toString(),
                  label: const Text('Min'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _replaceGroup(
                    group.copyWith(minSelections: parseMenuEditorInt(value)),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: ShadInputFormField(
                  initialValue: group.maxSelections.toString(),
                  label: const Text('Max'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _replaceGroup(
                    group.copyWith(maxSelections: parseMenuEditorInt(value)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Options', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final entry in group.options.asMap().entries)
            MenuModifierOptionRow(
              option: entry.value,
              onChanged: (option) => _replaceOption(entry.key, option),
              onRemoved: () => _removeOption(entry.key),
            ),
          ShadButton.ghost(
            onPressed: _addOption,
            child: const Text('Add option'),
          ),
        ],
      ),
    );
  }

  void _replaceGroup(MenuModifierGroupModel updated) {
    final groups = List<MenuModifierGroupModel>.from(item.modifierGroups);
    groups[groupIndex] = updated;
    onChanged(item.copyWith(modifierGroups: groups));
  }

  void _removeGroup() {
    final groups = List<MenuModifierGroupModel>.from(item.modifierGroups)
      ..removeAt(groupIndex);
    onChanged(item.copyWith(modifierGroups: groups));
  }

  void _addOption() {
    final options = List<MenuModifierOptionModel>.from(group.options)
      ..add(newMenuModifierOption(DateTime.now()));
    _replaceGroup(group.copyWith(options: options));
  }

  void _replaceOption(int optionIndex, MenuModifierOptionModel option) {
    final options = List<MenuModifierOptionModel>.from(group.options);
    options[optionIndex] = option;
    _replaceGroup(group.copyWith(options: options));
  }

  void _removeOption(int optionIndex) {
    final options = List<MenuModifierOptionModel>.from(group.options)
      ..removeAt(optionIndex);
    _replaceGroup(group.copyWith(options: options));
  }
}
