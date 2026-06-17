import '../../models/menu.dart';

MenuItemModel newMenuEditorItem(DateTime now) {
  return MenuItemModel(
    id: 'item-${now.millisecondsSinceEpoch}',
    name: 'New Item',
    priceCents: 0,
    available: true,
    category: '',
    modifiers: const [],
    modifierGroups: const [],
  );
}

MenuModifierGroupModel newMenuModifierGroup(DateTime now) {
  return MenuModifierGroupModel(
    id: 'group-${now.millisecondsSinceEpoch}',
    name: 'Group',
    required: false,
    minSelections: 0,
    maxSelections: 0,
    options: const [],
  );
}

MenuModifierOptionModel newMenuModifierOption(DateTime now) {
  return MenuModifierOptionModel(
    id: 'opt-${now.millisecondsSinceEpoch}',
    name: 'Option',
    priceCents: 0,
  );
}

BundleRuleModel newBundleRule(DateTime now) {
  return BundleRuleModel(
    bundleId: 'bundle-${now.millisecondsSinceEpoch}',
    displayName: 'Bundle',
    triggerItemId: '',
    triggerCategory: '',
    components: const [],
    promptHintsFr: '',
  );
}

BundleComponentModel newBundleComponent() {
  return BundleComponentModel(
    role: '',
    itemIdsCsv: '',
    category: '',
    requiredGroupIdsCsv: '',
  );
}

int parseMenuEditorInt(String value) {
  return int.tryParse(value) ?? 0;
}
