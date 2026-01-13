import 'fuel_order.dart';
import 'order_delivery.dart';
import 'order_item.dart';
import 'order_status.dart';

class Order {
  final String id;
  final String storeId;
  final String customerName;
  final String notes;
  final OrderStatus status;
  final String fulfillmentType;
  final OrderDelivery? delivery;
  final List<OrderItem> items;
  final int totalCents;
  final DateTime createdAt;
  final String businessType;
  final FuelOrder? fuel;
  final String paymentMethod;

  Order({
    required this.id,
    required this.storeId,
    required this.customerName,
    required this.notes,
    required this.status,
    required this.fulfillmentType,
    required this.delivery,
    required this.items,
    required this.totalCents,
    required this.createdAt,
    required this.businessType,
    required this.fuel,
    required this.paymentMethod,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final fulfillment = (json['fulfillmentType'] as String?)?.trim();
    final deliveryRaw = json['delivery'];
    final OrderDelivery? delivery = deliveryRaw is Map
        ? OrderDelivery.fromJson(deliveryRaw.cast<String, dynamic>())
        : null;
    final fuelRaw = json['fuel'];
    final FuelOrder? fuel = fuelRaw is Map
        ? FuelOrder.fromJson(fuelRaw.cast<String, dynamic>())
        : null;
    return Order(
      id: json['id'] ?? '',
      storeId: json['storeId'] ?? '',
      customerName: json['customerName'] ?? 'Customer',
      notes: json['notes'] ?? '',
      status: orderStatusFromString(json['status'] ?? 'pending'),
      fulfillmentType:
          (fulfillment == null || fulfillment.isEmpty) ? 'pickup' : fulfillment,
      delivery: delivery,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCents: json['totalCents'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      businessType: (json['businessType'] as String?)?.trim() ?? '',
      fuel: fuel,
      paymentMethod: (json['paymentMethod'] as String?)?.trim() ?? '',
    );
  }

  String get title => customerName.isNotEmpty ? customerName : id;
  bool get isGasOrder => businessType == 'gas_station' || fuel != null;
  bool get isCardPayment => paymentMethod.toLowerCase() == 'card';

  String itemsSummary() {
    if (items.isNotEmpty) {
      return items.map((e) => '${e.quantity}x ${e.name}').join(', ');
    }
    if (fuel != null) {
      final grade = fuel!.fuelGradeName.isNotEmpty
          ? fuel!.fuelGradeName
          : fuel!.fuelGradeId;
      final liters =
          fuel!.finalLiters > 0 ? fuel!.finalLiters : fuel!.requestedLiters;
      final litersLabel = liters > 0 ? '${liters.toStringAsFixed(2)} L' : '';
      final label = grade.isEmpty ? 'Fuel order' : 'Fuel: $grade';
      return litersLabel.isEmpty ? label : '$label - $litersLabel';
    }
    return '';
  }

  String get formattedTotal {
    final value = (totalCents / 100).toStringAsFixed(2);
    return isGasOrder ? 'EUR $value' : '\$$value';
  }
}
