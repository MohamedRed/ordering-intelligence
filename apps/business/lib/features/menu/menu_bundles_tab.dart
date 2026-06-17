import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/menu.dart';
import 'menu_bundle_rule_card.dart';
import 'menu_editor_factories.dart';

class MenuBundlesTab extends StatelessWidget {
  const MenuBundlesTab({
    super.key,
    required this.rules,
    required this.onRulesChanged,
  });

  final List<BundleRuleModel> rules;
  final ValueChanged<List<BundleRuleModel>> onRulesChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            onPressed: _addRule,
            child: const Text('Add bundle rule'),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in rules.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MenuBundleRuleCard(
              ruleIndex: entry.key,
              rule: entry.value,
              rules: rules,
              onRulesChanged: onRulesChanged,
            ),
          ),
      ],
    );
  }

  void _addRule() {
    final updated = List<BundleRuleModel>.from(rules)
      ..add(newBundleRule(DateTime.now()));
    onRulesChanged(updated);
  }
}
