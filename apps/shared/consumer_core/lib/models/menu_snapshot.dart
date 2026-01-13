import 'menu_item.dart';

class MenuSnapshot {
  final String storeId;
  final String updated;
  final List<MenuItem> items;

  const MenuSnapshot({
    required this.storeId,
    required this.updated,
    required this.items,
  });

  factory MenuSnapshot.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    final parsedItems = <MenuItem>[];
    if (itemsJson is List) {
      for (final item in itemsJson) {
        if (item is Map<String, dynamic>) {
          parsedItems.add(MenuItem.fromJson(item));
        }
      }
    }
    return MenuSnapshot(
      storeId: (json['storeId'] ?? '').toString(),
      updated: (json['updated'] ?? json['updatedAt'] ?? '').toString(),
      items: parsedItems,
    );
  }
}
