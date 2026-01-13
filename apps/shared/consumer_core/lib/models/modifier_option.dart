class ModifierOption {
  final String id;
  final String name;
  final int priceCents;

  const ModifierOption({
    required this.id,
    required this.name,
    required this.priceCents,
  });

  factory ModifierOption.fromJson(Map<String, dynamic> json) {
    return ModifierOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      priceCents: (json['priceCents'] ?? 0) is int
          ? json['priceCents'] as int
          : int.tryParse((json['priceCents'] ?? '0').toString()) ?? 0,
    );
  }
}
