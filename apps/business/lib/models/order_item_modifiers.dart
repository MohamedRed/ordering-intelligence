class OrderItemLegacyModifier {
  final String name;
  final int priceCents;

  OrderItemLegacyModifier({required this.name, required this.priceCents});

  factory OrderItemLegacyModifier.fromJson(Map<String, dynamic> json) =>
      OrderItemLegacyModifier(
        name: json['name'] ?? '',
        priceCents: json['priceCents'] ?? 0,
      );
}

class OrderItemModifierSelection {
  final String groupId;
  final String optionId;
  final String name;
  final int priceCents;

  OrderItemModifierSelection({
    required this.groupId,
    required this.optionId,
    required this.name,
    required this.priceCents,
  });

  factory OrderItemModifierSelection.fromJson(Map<String, dynamic> json) =>
      OrderItemModifierSelection(
        groupId: json['groupId'] ?? '',
        optionId: json['optionId'] ?? '',
        name: json['name'] ?? '',
        priceCents: json['priceCents'] ?? 0,
      );
}
