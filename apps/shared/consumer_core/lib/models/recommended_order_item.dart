import 'recommended_order_modifier.dart';

class RecommendedOrderItem {
  final String itemId;
  final String name;
  final int quantity;
  final String category;
  final List<RecommendedOrderModifier> modifiers;

  const RecommendedOrderItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.category,
    required this.modifiers,
  });

  factory RecommendedOrderItem.fromJson(Map<String, dynamic> json) {
    final rawModifiers = json['modifiers'];
    final parsedModifiers = <RecommendedOrderModifier>[];
    if (rawModifiers is List) {
      for (final entry in rawModifiers) {
        if (entry is Map<String, dynamic>) {
          parsedModifiers.add(RecommendedOrderModifier.fromJson(entry));
        }
      }
    }
    return RecommendedOrderItem(
      itemId: (json['itemId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      quantity: (json['quantity'] ?? 0) is int
          ? json['quantity'] as int
          : int.tryParse((json['quantity'] ?? '0').toString()) ?? 0,
      category: (json['category'] ?? '').toString(),
      modifiers: parsedModifiers,
    );
  }
}
