import 'dart:convert';

enum OrderStatus { pending, confirmed, ready, completed, cancelled }

OrderStatus orderStatusFromString(String value) {
  switch (value) {
    case 'pending':
      return OrderStatus.pending;
    case 'confirmed':
      return OrderStatus.confirmed;
    case 'ready':
      return OrderStatus.ready;
    case 'completed':
      return OrderStatus.completed;
    case 'cancelled':
      return OrderStatus.cancelled;
    default:
      return OrderStatus.pending;
  }
}

class OrderItem {
  final String itemId;
  final String name;
  final int quantity;
  final int priceCents;
  final List<String> modifiers;

  OrderItem({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.priceCents,
    required this.modifiers,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      itemId: json['itemId'] ?? '',
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 0,
      priceCents: json['priceCents'] ?? 0,
      modifiers: (json['modifiers'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class Order {
  final String id;
  final String storeId;
  final String customerName;
  final String notes;
  final OrderStatus status;
  final List<OrderItem> items;
  final int totalCents;
  final DateTime createdAt;

  Order({
    required this.id,
    required this.storeId,
    required this.customerName,
    required this.notes,
    required this.status,
    required this.items,
    required this.totalCents,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] ?? '',
      storeId: json['storeId'] ?? '',
      customerName: json['customerName'] ?? 'Customer',
      notes: json['notes'] ?? '',
      status: orderStatusFromString(json['status'] ?? 'pending'),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCents: json['totalCents'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get title => customerName.isNotEmpty ? customerName : id;

  String itemsSummary() {
    return items.map((e) => '${e.quantity}× ${e.name}').join(', ');
  }

  String get formattedTotal => '\$${(totalCents / 100).toStringAsFixed(2)}';
}
