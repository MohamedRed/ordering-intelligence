import '../models/cart_models.dart';
import '../models/draft_order.dart';
import '../models/menu_item.dart';
import '../models/menu_snapshot.dart';

class DraftOrderLogic {
  const DraftOrderLogic._();

  static int itemCount(DraftOrder draft) {
    return draft.items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  static int totalCents(DraftOrder draft) {
    return draft.items.fold<int>(0, (sum, item) {
      final modifierTotal = item.modifiers.fold<int>(
        0,
        (modSum, modifier) => modSum + modifier.priceCents,
      );
      final line = (item.priceCents + modifierTotal) * item.quantity;
      return sum + line;
    });
  }

  static List<DraftOrderItem> itemsFromCart(List<CartItem> cart) {
    return cart
        .map(
          (item) => DraftOrderItem(
            itemId: item.item.id,
            name: item.item.name,
            priceCents: item.item.priceCents,
            quantity: item.quantity,
            modifiers: item.selections
                .map(
                  (sel) => DraftOrderModifier(
                    groupId: sel.groupId,
                    optionId: sel.optionId,
                    name: sel.name,
                    priceCents: sel.priceCents,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  static List<CartItem> cartFromDraft(DraftOrder draft, MenuSnapshot? menu) {
    final items = <CartItem>[];
    for (final draftItem in draft.items) {
      final menuItem = _resolveMenuItem(draftItem, menu);
      final selections = draftItem.modifiers
          .map(
            (modifier) => ModifierSelection(
              groupId: modifier.groupId,
              optionId: modifier.optionId,
              name: modifier.name,
              priceCents: modifier.priceCents,
            ),
          )
          .toList();
      items.add(
        CartItem(
          item: menuItem,
          quantity: draftItem.quantity,
          selections: selections,
        ),
      );
    }
    return items;
  }

  static MenuItem _resolveMenuItem(DraftOrderItem item, MenuSnapshot? menu) {
    if (menu != null) {
      for (final menuItem in menu.items) {
        if (menuItem.id == item.itemId) {
          return menuItem;
        }
      }
    }
    return MenuItem(
      id: item.itemId,
      name: item.name,
      category: '',
      description: '',
      priceCents: item.priceCents,
      available: true,
      modifierGroups: const [],
      imageUrl: '',
    );
  }
}
