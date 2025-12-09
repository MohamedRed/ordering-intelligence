class OrderSummary {
  final int total;
  final Map<String, int> statusCounts;
  final Map<String, int> last24hCounts;

  OrderSummary(
      {required this.total,
      required this.statusCounts,
      required this.last24hCounts});

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    Map<String, int> toMap(dynamic m) {
      return (m as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    return OrderSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      statusCounts: toMap(json['statusCounts']),
      last24hCounts: toMap(json['last24hCounts']),
    );
  }
}
