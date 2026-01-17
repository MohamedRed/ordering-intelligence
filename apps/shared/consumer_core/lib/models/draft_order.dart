import 'delivery_models.dart';

class DraftOrderModifier {
  final String groupId;
  final String optionId;
  final String name;
  final int priceCents;

  const DraftOrderModifier({
    required this.groupId,
    required this.optionId,
    required this.name,
    required this.priceCents,
  });

  factory DraftOrderModifier.fromJson(Map<String, dynamic> json) {
    return DraftOrderModifier(
      groupId: (json['groupId'] ?? '').toString(),
      optionId: (json['optionId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      priceCents: (json['priceCents'] ?? 0) is int
          ? json['priceCents'] as int
          : int.tryParse((json['priceCents'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'optionId': optionId,
        'name': name,
        'priceCents': priceCents,
      };
}

class DraftOrderItem {
  final String itemId;
  final String name;
  final int priceCents;
  final int quantity;
  final List<DraftOrderModifier> modifiers;

  const DraftOrderItem({
    required this.itemId,
    required this.name,
    required this.priceCents,
    required this.quantity,
    required this.modifiers,
  });

  factory DraftOrderItem.fromJson(Map<String, dynamic> json) {
    final modifiersJson = json['modifiers'];
    final parsedModifiers = <DraftOrderModifier>[];
    if (modifiersJson is List) {
      for (final modifier in modifiersJson) {
        if (modifier is Map<String, dynamic>) {
          parsedModifiers.add(DraftOrderModifier.fromJson(modifier));
        }
      }
    }
    return DraftOrderItem(
      itemId: (json['itemId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      priceCents: (json['priceCents'] ?? 0) is int
          ? json['priceCents'] as int
          : int.tryParse((json['priceCents'] ?? '0').toString()) ?? 0,
      quantity: (json['quantity'] ?? 0) is int
          ? json['quantity'] as int
          : int.tryParse((json['quantity'] ?? '0').toString()) ?? 0,
      modifiers: parsedModifiers,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'priceCents': priceCents,
        'quantity': quantity,
        'modifiers': modifiers.map((modifier) => modifier.toJson()).toList(),
      };
}

class DraftOrderDelivery {
  final String addressText;
  final String instructions;
  final DeliveryLatLng? dropoffLatLng;
  final DeliveryAddress? dropoffAddress;

  const DraftOrderDelivery({
    this.addressText = '',
    this.instructions = '',
    this.dropoffLatLng,
    this.dropoffAddress,
  });

  factory DraftOrderDelivery.fromJson(Map<String, dynamic> json) {
    return DraftOrderDelivery(
      addressText: (json['addressText'] ?? '').toString(),
      instructions: (json['instructions'] ?? '').toString(),
      dropoffLatLng: json['dropoffLatLng'] is Map<String, dynamic>
          ? DeliveryLatLng.fromJson(
              (json['dropoffLatLng'] as Map<String, dynamic>),
            )
          : null,
      dropoffAddress: json['dropoffAddress'] is Map<String, dynamic>
          ? DeliveryAddress.fromJson(
              (json['dropoffAddress'] as Map<String, dynamic>),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'addressText': addressText,
        'instructions': instructions,
        if (dropoffLatLng != null) 'dropoffLatLng': dropoffLatLng!.toJson(),
        if (dropoffAddress != null) 'dropoffAddress': dropoffAddress!.toJson(),
      };
}

class DraftOrder {
  final String id;
  final String storeId;
  final String orderType;
  final String groupOrderId;
  final String fulfillmentType;
  final String notes;
  final List<DraftOrderItem> items;
  final DraftOrderDelivery? delivery;
  final int version;
  final String updatedAt;
  final String expiresAt;

  const DraftOrder({
    required this.id,
    required this.storeId,
    required this.orderType,
    this.groupOrderId = '',
    this.fulfillmentType = 'pickup',
    this.notes = '',
    this.items = const [],
    this.delivery,
    this.version = 0,
    this.updatedAt = '',
    this.expiresAt = '',
  });

  factory DraftOrder.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    final parsedItems = <DraftOrderItem>[];
    if (itemsJson is List) {
      for (final item in itemsJson) {
        if (item is Map<String, dynamic>) {
          parsedItems.add(DraftOrderItem.fromJson(item));
        }
      }
    }
    final deliveryJson = json['delivery'];
    return DraftOrder(
      id: (json['id'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      orderType: (json['orderType'] ?? '').toString(),
      groupOrderId: (json['groupOrderId'] ?? '').toString(),
      fulfillmentType: (json['fulfillmentType'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      items: parsedItems,
      delivery: deliveryJson is Map<String, dynamic>
          ? DraftOrderDelivery.fromJson(deliveryJson)
          : null,
      version: (json['version'] ?? 0) is int
          ? json['version'] as int
          : int.tryParse((json['version'] ?? '0').toString()) ?? 0,
      updatedAt: (json['updatedAt'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'orderType': orderType,
        if (groupOrderId.isNotEmpty) 'groupOrderId': groupOrderId,
        'fulfillmentType': fulfillmentType,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        'items': items.map((item) => item.toJson()).toList(),
        if (delivery != null) 'delivery': delivery!.toJson(),
        if (version > 0) 'version': version,
      };

  bool get hasData {
    return items.isNotEmpty ||
        notes.trim().isNotEmpty ||
        (delivery != null &&
            (delivery!.addressText.trim().isNotEmpty ||
                delivery!.instructions.trim().isNotEmpty ||
                delivery!.dropoffAddress != null ||
                delivery!.dropoffLatLng != null));
  }
}
