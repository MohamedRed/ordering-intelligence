class MenuJob {
  const MenuJob({
    required this.id,
    required this.restaurantId,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String status;
  final int updatedAt;

  factory MenuJob.fromJson(Map<String, dynamic> json) => MenuJob(
        id: json['jobId']?.toString() ?? '',
        restaurantId: json['restaurantId']?.toString() ?? '',
        status: json['status']?.toString() ?? 'unknown',
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class AgentJob {
  const AgentJob({
    required this.id,
    required this.status,
    required this.prompt,
    required this.fileUri,
    required this.updatedAt,
  });

  final String id;
  final String status;
  final String prompt;
  final String fileUri;
  final int updatedAt;

  factory AgentJob.fromJson(Map<String, dynamic> json) => AgentJob(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'unknown',
        prompt: json['prompt']?.toString() ?? '',
        fileUri: json['fileUri']?.toString() ?? '',
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class DraftDetail {
  const DraftDetail({
    required this.items,
    required this.fileUrls,
    required this.compositeUrls,
  });

  final List<DraftItem> items;
  final List<String> fileUrls;
  final List<String> compositeUrls;

  factory DraftDetail.fromJson(Map<String, dynamic> json) {
    final draft = Map<String, dynamic>.from(
      (json['draft'] as Map?) ?? const <String, dynamic>{},
    );
    return DraftDetail(
      items: ((draft['items'] ?? const []) as List)
          .map((e) => DraftItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      fileUrls: (json['fileUrls'] as List?)
              ?.map((e) => e.toString())
              .where((url) => url.isNotEmpty)
              .toList() ??
          const [],
      compositeUrls: (draft['compositeUrls'] as List?)
              ?.map((e) => e.toString())
              .where((url) => url.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class DraftItem {
  const DraftItem({
    required this.name,
    required this.available,
    this.category,
    this.price,
    this.imageUrl,
    this.photoUrl,
  });

  final String name;
  final String? category;
  final num? price;
  final bool available;
  final String? imageUrl;
  final String? photoUrl;

  factory DraftItem.fromJson(Map<String, dynamic> json) => DraftItem(
        name: json['name']?.toString() ?? 'Unnamed',
        category: json['category'] as String?,
        price: json['price'] as num?,
        available: json['available'] as bool? ?? true,
        imageUrl: json['imageUrl'] as String?,
        photoUrl: json['photoUrl'] as String?,
      );
}
