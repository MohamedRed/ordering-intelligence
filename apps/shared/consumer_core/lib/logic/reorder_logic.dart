import '../models/cart_models.dart';
import '../models/menu_models.dart';
import '../models/recommended_order.dart';
import '../models/recommended_order_modifier.dart';

class ReorderApplyResult {
  final List<CartItem> cart;
  final int addedCount;
  final int missingCount;

  const ReorderApplyResult({
    required this.cart,
    required this.addedCount,
    required this.missingCount,
  });
}

class ReorderLogic {
  const ReorderLogic._();

  static ReorderApplyResult apply({
    required MenuSnapshot menu,
    required List<CartItem> cart,
    required RecommendedOrder order,
  }) {
    var nextCart = List<CartItem>.from(cart);
    var added = 0;
    var missing = 0;

    for (final entry in order.items) {
      final menuItem = menu.items.firstWhere(
        (item) => item.id == entry.itemId,
        orElse: () => MenuItem(
          id: '',
          name: '',
          category: '',
          description: '',
          priceCents: 0,
          available: false,
          modifierGroups: const [],
          imageUrl: '',
        ),
      );
      if (menuItem.id.isEmpty) {
        missing += entry.quantity > 0 ? entry.quantity : 1;
        continue;
      }
      final selections = _matchModifierSelections(menuItem, entry.modifiers);
      final qty = entry.quantity > 0 ? entry.quantity : 1;
      for (var i = 0; i < qty; i++) {
        nextCart = _addToCart(nextCart, menuItem, selections);
        added += 1;
      }
    }

    return ReorderApplyResult(
      cart: nextCart,
      addedCount: added,
      missingCount: missing,
    );
  }

  static List<CartItem> _addToCart(
    List<CartItem> cart,
    MenuItem item,
    List<ModifierSelection> selections,
  ) {
    final next = List<CartItem>.from(cart);
    final newItem = CartItem(item: item, quantity: 1, selections: selections);
    final index = next.indexWhere((entry) => entry.key == newItem.key);
    if (index >= 0) {
      final existing = next[index];
      next[index] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      next.add(newItem);
    }
    return next;
  }

  static List<ModifierSelection> _matchModifierSelections(
    MenuItem item,
    List<RecommendedOrderModifier> modifiers,
  ) {
    if (modifiers.isEmpty || item.modifierGroups.isEmpty) {
      return const [];
    }
    final selections = <ModifierSelection>[];
    for (final modifier in modifiers) {
      for (final group in item.modifierGroups) {
        final match = group.options.firstWhere(
          (option) =>
              option.name.toLowerCase() == modifier.name.toLowerCase() &&
              (modifier.priceCents == 0 || option.priceCents == modifier.priceCents),
          orElse: () => const ModifierOption(
            id: '',
            name: '',
            priceCents: 0,
          ),
        );
        if (match.id.isNotEmpty) {
          selections.add(
            ModifierSelection(
              groupId: group.id,
              optionId: match.id,
              name: match.name,
              priceCents: match.priceCents,
            ),
          );
          break;
        }
      }
    }
    return selections;
  }
}
