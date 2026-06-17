import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/menu/menu_editor_factories.dart';

void main() {
  test('menu editor factories create stable default editing records', () {
    final now = DateTime.fromMillisecondsSinceEpoch(12345);

    final item = newMenuEditorItem(now);
    expect(item.id, 'item-12345');
    expect(item.name, 'New Item');
    expect(item.available, isTrue);
    expect(item.modifierGroups, isEmpty);

    final group = newMenuModifierGroup(now);
    expect(group.id, 'group-12345');
    expect(group.required, isFalse);
    expect(group.options, isEmpty);

    final option = newMenuModifierOption(now);
    expect(option.id, 'opt-12345');
    expect(option.priceCents, 0);

    final rule = newBundleRule(now);
    expect(rule.bundleId, 'bundle-12345');
    expect(rule.displayName, 'Bundle');
    expect(rule.components, isEmpty);

    final component = newBundleComponent();
    expect(component.role, isEmpty);
    expect(component.itemIdsCsv, isEmpty);
  });

  test('menu editor integer parser treats invalid input as zero', () {
    expect(parseMenuEditorInt('250'), 250);
    expect(parseMenuEditorInt('not-a-number'), 0);
    expect(parseMenuEditorInt(''), 0);
  });
}
