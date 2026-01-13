import '../models/cart_models.dart';

class CartLogic {
  const CartLogic._();

  static int itemCount(List<CartItem> items) {
    return items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  static int totalCents(List<CartItem> items) {
    return items.fold<int>(0, (sum, item) => sum + item.lineTotalCents);
  }

  static List<CartItem> addItem(List<CartItem> items, CartItem newItem) {
    final next = List<CartItem>.from(items);
    final index = next.indexWhere((entry) => entry.key == newItem.key);
    if (index >= 0) {
      final existing = next[index];
      next[index] = existing.copyWith(quantity: existing.quantity + newItem.quantity);
    } else {
      next.add(newItem);
    }
    return next;
  }

  static List<CartItem> updateQuantity(List<CartItem> items, CartItem item, int delta) {
    final next = List<CartItem>.from(items);
    final index = next.indexWhere((entry) => entry.key == item.key);
    if (index == -1) {
      return next;
    }
    final current = next[index];
    final nextQty = current.quantity + delta;
    if (nextQty <= 0) {
      next.removeAt(index);
    } else {
      next[index] = current.copyWith(quantity: nextQty);
    }
    return next;
  }

  static List<CartItem> clear() => const <CartItem>[];
}
