import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_editor_factories.dart';

class MenuBundleRuleCard extends StatelessWidget {
  const MenuBundleRuleCard({
    super.key,
    required this.ruleIndex,
    required this.rule,
    required this.rules,
    required this.onRulesChanged,
  });

  final int ruleIndex;
  final BundleRuleModel rule;
  final List<BundleRuleModel> rules;
  final ValueChanged<List<BundleRuleModel>> onRulesChanged;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
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
                  onChanged: (value) =>
                      _replaceRule(rule.copyWith(displayName: value)),
                ),
              ),
              IconButton(
                onPressed: _removeRule,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: rule.bundleId,
            label: const Text('Bundle ID'),
            onChanged: (value) => _replaceRule(rule.copyWith(bundleId: value)),
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: rule.triggerItemId,
            label: const Text('Trigger item ID (optional)'),
            onChanged: (value) =>
                _replaceRule(rule.copyWith(triggerItemId: value)),
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: rule.triggerCategory,
            label: const Text('Trigger category (optional)'),
            onChanged: (value) =>
                _replaceRule(rule.copyWith(triggerCategory: value)),
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: rule.promptHintsFr,
            label: const Text('Prompt hints FR (optional)'),
            onChanged: (value) =>
                _replaceRule(rule.copyWith(promptHintsFr: value)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Components', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              ShadButton.ghost(
                onPressed: _addComponent,
                child: const Text('Add component'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final entry in rule.components.asMap().entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BundleComponentCard(
                component: entry.value,
                onChanged: (component) =>
                    _replaceComponent(entry.key, component),
                onRemoved: () => _removeComponent(entry.key),
              ),
            ),
        ],
      ),
    );
  }

  void _replaceRule(BundleRuleModel updatedRule) {
    final updated = List<BundleRuleModel>.from(rules);
    updated[ruleIndex] = updatedRule;
    onRulesChanged(updated);
  }

  void _removeRule() {
    final updated = List<BundleRuleModel>.from(rules)..removeAt(ruleIndex);
    onRulesChanged(updated);
  }

  void _addComponent() {
    final components = List<BundleComponentModel>.from(rule.components)
      ..add(newBundleComponent());
    _replaceRule(rule.copyWith(components: components));
  }

  void _replaceComponent(int index, BundleComponentModel component) {
    final components = List<BundleComponentModel>.from(rule.components);
    components[index] = component;
    _replaceRule(rule.copyWith(components: components));
  }

  void _removeComponent(int index) {
    final components = List<BundleComponentModel>.from(rule.components)
      ..removeAt(index);
    _replaceRule(rule.copyWith(components: components));
  }
}

class _BundleComponentCard extends StatelessWidget {
  const _BundleComponentCard({
    required this.component,
    required this.onChanged,
    required this.onRemoved,
  });

  final BundleComponentModel component;
  final ValueChanged<BundleComponentModel> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ShadInputFormField(
                  initialValue: component.role,
                  label: const Text('Role (drink/side/...)'),
                  onChanged: (value) =>
                      onChanged(component.copyWith(role: value)),
                ),
              ),
              IconButton(
                onPressed: onRemoved,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: component.category,
            label: const Text('Allowed category (optional)'),
            onChanged: (value) =>
                onChanged(component.copyWith(category: value)),
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: component.itemIdsCsv,
            label: const Text('Allowed item IDs (csv, optional)'),
            onChanged: (value) =>
                onChanged(component.copyWith(itemIdsCsv: value)),
          ),
          const SizedBox(height: 8),
          ShadInputFormField(
            initialValue: component.requiredGroupIdsCsv,
            label: const Text('Required group IDs (csv, optional)'),
            onChanged: (value) =>
                onChanged(component.copyWith(requiredGroupIdsCsv: value)),
          ),
        ],
      ),
    );
  }
}
