import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/orders/inbox/order_delivery_helpers.dart';
import 'package:business_app/features/orders/inbox/order_inbox_filters.dart';
import 'package:business_app/features/orders/inbox/order_inbox_utils.dart';
import 'package:business_app/features/orders/inbox/order_list_actions.dart';
import 'package:business_app/models/group_order.dart';
import 'package:business_app/models/order.dart';

void main() {
  test('filterOrdersForInbox narrows delivery orders by normalized status', () {
    final orders = [
      _order(
        id: 'pickup-1',
        fulfillmentType: 'pickup',
        deliverySummary: '',
      ),
      _order(
        id: 'delivery-1',
        fulfillmentType: 'delivery',
        deliverySummary: 'Out for delivery',
      ),
      _order(
        id: 'delivery-2',
        fulfillmentType: 'delivery',
        deliverySummary: 'Delivered',
      ),
    ];

    final delivery = filterOrdersForInbox(
      orders,
      OrderInboxFilter.delivery,
      'all',
    );
    final outForDelivery = filterOrdersForInbox(
      orders,
      OrderInboxFilter.delivery,
      'out_for_delivery',
    );

    expect(delivery.map((order) => order.id), ['delivery-1', 'delivery-2']);
    expect(outForDelivery.map((order) => order.id), ['delivery-1']);
    expect(deliveryStatusLabelForOrder(orders[1]), 'Out for delivery');
    expect(deliveryStatusColor('failed').toARGB32(), isNonZero);
  });

  test('group order filters include submitted orders and sort operationally',
      () {
    final submittedOld = _groupOrder(
      id: 'submitted-old',
      status: 'submitted',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final submittedNew = _groupOrder(
      id: 'submitted-new',
      status: 'submitted',
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final paid = _groupOrder(
      id: 'paid',
      status: 'paid',
      updatedAt: DateTime.utc(2026, 1, 3),
    );

    expect(isGroupOrderSubmitted(submittedOld), isTrue);
    expect(
      filterGroupOrdersForInbox(
        [submittedOld, paid, submittedNew],
        OrderInboxFilter.all,
      ).map((order) => order.id),
      ['submitted-old', 'submitted-new'],
    );
    expect(
      sortGroupOrdersForInbox([submittedOld, paid, submittedNew])
          .map((order) => order.id),
      ['paid', 'submitted-new', 'submitted-old'],
    );
  });

  test('order status actions advance through fulfillment workflow', () {
    expect(nextOrderActions(OrderStatus.pending), [
      OrderStatus.confirmed,
      OrderStatus.cancelled,
    ]);
    expect(orderStatusLabel(OrderStatus.ready), 'Ready');
    expect(orderStatusColor(OrderStatus.completed).toARGB32(), isNonZero);
  });
}

Order _order({
  required String id,
  required String fulfillmentType,
  required String deliverySummary,
}) {
  return Order.fromJson({
    'id': id,
    'storeId': 'store-1',
    'customerName': 'Customer $id',
    'status': 'pending',
    'fulfillmentType': fulfillmentType,
    'items': [
      {'name': 'Pizza', 'quantity': 2, 'priceCents': 1200},
    ],
    'totalCents': 2400,
    'createdAt': '2026-01-01T10:00:00Z',
    if (fulfillmentType == 'delivery')
      'delivery': {
        'fleetMode': 'owned',
        'assignmentStatus': deliverySummary,
        'deliveryStatusSummary': deliverySummary,
      },
  });
}

GroupOrder _groupOrder({
  required String id,
  required String status,
  required DateTime updatedAt,
}) {
  return GroupOrder.fromJson({
    'id': id,
    'joinCode': 'JOIN',
    'storeId': 'store-1',
    'status': status,
    'host': {'displayName': 'Host'},
    'items': [
      {'name': 'Fries', 'quantity': 1, 'priceCents': 500},
    ],
    'updatedAt': updatedAt.toIso8601String(),
  });
}
