import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/models/menu.dart';

void main() {
  test('MenuRecordModel derives legacy modifier groups and roundtrips bundles',
      () {
    final record = MenuRecordModel.fromJson({
      'items': [
        {
          'id': 'burger',
          'name': 'Burger',
          'priceCents': 1200,
          'available': true,
          'category': 'mains',
          'modifiers': [
            {'name': 'Extra Cheese', 'priceCents': 150},
          ],
        },
      ],
      'bundleRules': [
        {
          'bundleId': 'meal',
          'displayName': 'Meal',
          'triggerItemId': 'burger',
          'components': [
            {
              'role': 'side',
              'itemIds': ['fries', 'salad'],
              'requiredGroupIds': ['legacy_modifiers'],
            },
          ],
          'promptHintsFr': 'Proposer un menu.',
        },
      ],
    });

    final item = record.items.single;
    expect(item.modifierGroups.single.id, 'legacy_modifiers');
    expect(item.modifierGroups.single.options.single.id, 'extra-cheese');
    expect(item.modifierGroups.single.options.single.priceCents, 150);

    final bundle = record.bundleRules.single;
    expect(bundle.components.single.itemIdsCsv, 'fries,salad');
    expect(bundle.components.single.requiredGroupIdsCsv, 'legacy_modifiers');

    final json = record.toJson();
    expect(json['items'], isA<List<dynamic>>());
    expect(json['bundleRules'], isA<List<dynamic>>());
    expect(
      (json['bundleRules'] as List).single['components'].single['itemIds'],
      ['fries', 'salad'],
    );
  });

  test('menu helpers trim CSV values and produce stable ids', () {
    expect(splitCsv(' fries, , salad ,'), ['fries', 'salad']);
    expect(safeId(' Extra Cheese! '), 'extra-cheese');
    expect(safeId(' !!! '), 'id');
  });
}
