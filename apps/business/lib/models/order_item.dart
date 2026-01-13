import 'order_item_modifiers.dart';

class OrderItem {
  final String itemId;
  final String name;
  final int quantity;
  final int priceCents;
  final String participantId;
  final String participantLabel;
  final String category;
  final String bundleId;
  final String bundleRole;
  final List<OrderItemModifierSelection> modifierSelections;
  final List<OrderItemLegacyModifier> legacyModifiers;

  OrderItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.priceCents,
    required this.participantId,
    required this.participantLabel,
    required this.category,
    required this.bundleId,
    required this.bundleRole,
    required this.modifierSelections,
    required this.legacyModifiers,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final rawSelections = json['modifierSelections'];
    final modifierSelections =
        (rawSelections is List ? rawSelections : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(OrderItemModifierSelection.fromJson)
            .toList();

    final rawLegacy = json['modifiers'];
    final legacyModifiers = (rawLegacy is List ? rawLegacy : const <dynamic>[])
        .map<OrderItemLegacyModifier>((e) {
          if (e is String) {
            return OrderItemLegacyModifier(name: e, priceCents: 0);
          }
          if (e is Map<String, dynamic>) {
            return OrderItemLegacyModifier.fromJson(e);
          }
          if (e is Map) {
            return OrderItemLegacyModifier.fromJson(e.cast<String, dynamic>());
          }
          return OrderItemLegacyModifier(name: '', priceCents: 0);
        })
        .where((m) => m.name.trim().isNotEmpty)
        .toList();

    return OrderItem(
      itemId: json['itemId'] ?? '',
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 0,
      priceCents: json['priceCents'] ?? 0,
      participantId: json['participantId'] ?? '',
      participantLabel: json['participantLabel'] ?? '',
      category: json['category'] ?? '',
      bundleId: json['bundleId'] ?? '',
      bundleRole: json['bundleRole'] ?? '',
      modifierSelections: modifierSelections,
      legacyModifiers: legacyModifiers,
    );
  }

  List<String> get modifierLabels {
    if (modifierSelections.isNotEmpty) {
      return modifierSelections
          .map((s) => s.name)
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return legacyModifiers
        .map((m) => m.name)
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }
}
