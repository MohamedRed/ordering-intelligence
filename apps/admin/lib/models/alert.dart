class AlertItem {
  final String id;
  final String title;
  final String body;
  final String severity;
  final DateTime createdAt;

  AlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.createdAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      severity: json['severity'] ?? 'info',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}
