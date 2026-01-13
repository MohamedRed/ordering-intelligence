import 'modifier_group.dart';

class MenuItem {
  final String id;
  final String name;
  final String category;
  final String description;
  final int priceCents;
  final bool available;
  final List<ModifierGroup> modifierGroups;
  final String imageUrl;

  const MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.priceCents,
    required this.available,
    required this.modifierGroups,
    required this.imageUrl,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final groupsJson = json['modifierGroups'];
    final parsedGroups = <ModifierGroup>[];
    if (groupsJson is List) {
      for (final group in groupsJson) {
        if (group is Map<String, dynamic>) {
          parsedGroups.add(ModifierGroup.fromJson(group));
        }
      }
    }
    final imageUrl =
        (json['imageUrl'] ??
                json['image_url'] ??
                json['image'] ??
                json['photoUrl'] ??
                json['photo_url'] ??
                json['thumbnailUrl'] ??
                json['thumbnail_url'] ??
                '')
            .toString();
    return MenuItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      priceCents: (json['priceCents'] ?? 0) is int
          ? json['priceCents'] as int
          : int.tryParse((json['priceCents'] ?? '0').toString()) ?? 0,
      available: json['available'] == null ? true : json['available'] == true,
      modifierGroups: parsedGroups,
      imageUrl: imageUrl,
    );
  }
}
