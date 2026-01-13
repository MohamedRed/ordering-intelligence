class RecommendedOrderModifier {
  final String name;
  final int priceCents;

  const RecommendedOrderModifier({
    required this.name,
    required this.priceCents,
  });

  factory RecommendedOrderModifier.fromJson(Map<String, dynamic> json) {
    return RecommendedOrderModifier(
      name: (json['name'] ?? '').toString(),
      priceCents: (json['priceCents'] ?? 0) is int
          ? json['priceCents'] as int
          : int.tryParse((json['priceCents'] ?? '0').toString()) ?? 0,
    );
  }
}
