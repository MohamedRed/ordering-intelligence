import 'package:consumer_core/consumer_core.dart';

class ReorderHandoffItem {
  const ReorderHandoffItem({
    required this.itemId,
    required this.quantity,
  });

  final String itemId;
  final int quantity;
}

class ReorderHandoff {
  const ReorderHandoff({
    required this.storeId,
    required this.items,
    this.title = '',
    this.currency = '',
  });

  final String storeId;
  final List<ReorderHandoffItem> items;
  final String title;
  final String currency;

  int get itemCount =>
      items.fold<int>(0, (total, item) => total + item.quantity);

  RecommendedOrder toRecommendedOrder({StoreChoice? store}) {
    final storeName = store?.name ?? '';
    final tenantId = store?.tenantId ?? '';
    final businessType = store?.businessType ?? '';
    final logoUrl = store?.logoUrl ?? '';
    return RecommendedOrder(
      storeId: storeId,
      storeName: storeName,
      tenantId: tenantId,
      businessType: businessType,
      logoUrl: logoUrl,
      title: title,
      itemCount: itemCount,
      orderedAtIso: '',
      items: items
          .map(
            (item) => RecommendedOrderItem(
              itemId: item.itemId,
              name: '',
              quantity: item.quantity,
              category: '',
              modifiers: const [],
            ),
          )
          .toList(),
      currency: currency,
    );
  }
}
