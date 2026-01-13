import 'menu_models.dart';

class ModifierSelection {
  final String groupId;
  final String optionId;
  final String name;
  final int priceCents;

  const ModifierSelection({
    required this.groupId,
    required this.optionId,
    required this.name,
    required this.priceCents,
  });

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'optionId': optionId,
      'name': name,
      'priceCents': priceCents,
    };
  }
}

class CartItem {
  final MenuItem item;
  final int quantity;
  final List<ModifierSelection> selections;

  const CartItem({
    required this.item,
    required this.quantity,
    required this.selections,
  });

  CartItem copyWith({int? quantity, List<ModifierSelection>? selections}) {
    return CartItem(
      item: item,
      quantity: quantity ?? this.quantity,
      selections: selections ?? this.selections,
    );
  }

  int get lineTotalCents {
    final modifiersTotal = selections.fold<int>(
      0,
      (sum, sel) => sum + sel.priceCents,
    );
    return quantity * (item.priceCents + modifiersTotal);
  }

  String get key {
    final modifierKey =
        selections.map((sel) => '${sel.groupId}:${sel.optionId}').toList()
          ..sort();
    return '${item.id}|${modifierKey.join(',')}';
  }

  List<Map<String, dynamic>> toModifierSelectionsJson() {
    if (selections.isEmpty) {
      return [];
    }
    return selections.map((sel) => sel.toJson()).toList();
  }
}
