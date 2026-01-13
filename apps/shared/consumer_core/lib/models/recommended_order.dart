export 'recommended_order_item.dart';
export 'recommended_order_modifier.dart';

import 'fuel_order.dart';
import 'recommended_order_item.dart';

class RecommendedOrder {
  final String storeId;
  final String storeName;
  final String tenantId;
  final String businessType;
  final String logoUrl;
  final String title;
  final int itemCount;
  final String orderedAtIso;
  final List<RecommendedOrderItem> items;
  final FuelOrderDraft? fuel;
  final String currency;

  const RecommendedOrder({
    required this.storeId,
    required this.storeName,
    required this.tenantId,
    required this.businessType,
    required this.logoUrl,
    required this.title,
    required this.itemCount,
    required this.orderedAtIso,
    required this.items,
    this.fuel,
    this.currency = '',
  });

  factory RecommendedOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = <RecommendedOrderItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          parsedItems.add(RecommendedOrderItem.fromJson(entry));
        }
      }
    }
    final fuelRaw = json['fuel'];
    final FuelOrderDraft? fuel =
        fuelRaw is Map<String, dynamic> ? FuelOrderDraft.fromJson(fuelRaw) : null;
    final rawItemCount = (json['itemCount'] ?? 0);
    final parsedItemCount = rawItemCount is int
        ? rawItemCount
        : int.tryParse(rawItemCount.toString()) ?? 0;
    final itemCount = parsedItemCount == 0 && fuel != null ? 1 : parsedItemCount;
    return RecommendedOrder(
      storeId: (json['storeId'] ?? '').toString(),
      storeName: (json['storeName'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      businessType: (json['businessType'] ?? '').toString(),
      logoUrl: (json['logoUrl'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      itemCount: itemCount,
      orderedAtIso: (json['orderedAt'] ?? json['orderedAtIso'] ?? '').toString(),
      items: parsedItems,
      fuel: fuel,
      currency: (json['currency'] ?? '').toString(),
    );
  }

  bool get isFuelOrder => fuel != null;
}
