import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/orders/order_delivery_helpers.dart';
import 'package:business_app/features/orders/order_detail_items_section.dart';
import 'package:business_app/features/orders/order_status_helpers.dart';
import 'package:business_app/models/order.dart';

void main() {
  test('order detail status helpers preserve workflow transitions', () {
    expect(orderStatusLabel(OrderStatus.ready), 'Ready');
    expect(nextOrderStatusActions(OrderStatus.pending), [
      OrderStatus.confirmed,
      OrderStatus.cancelled,
    ]);
    expect(nextOrderStatusActions(OrderStatus.completed), isEmpty);
    expect(nextOrderStatusActions(OrderStatus.cancelled), isEmpty);
  });

  test('order detail delivery helpers normalize summaries', () {
    final order = Order.fromJson({
      'id': 'order-1',
      'fulfillmentType': 'delivery',
      'delivery': {
        'assignmentStatus': 'assigned',
        'deliveryStatusSummary': 'en route to customer',
      },
    });
    const quote = DeliveryQuote(
      provider: 'owned',
      providerFeeCents: 450,
      dropoffEtaMinutes: 18,
      currency: 'USD',
      quoteExpiresAt: null,
    );

    expect(deliveryStatusKey(order), 'out_for_delivery');
    expect(deliveryStatusLabel(order), 'Out for delivery');
    expect(formatOrderMoney(450), r'$4.50');
    expect(quoteSummary(quote), r'owned • ETA 18 min • Fee $4.50');
  });

  test('bundle role sort key keeps menu bundles in expected order', () {
    expect(bundleRoleSortKey('main'), lessThan(bundleRoleSortKey('side')));
    expect(bundleRoleSortKey('side'), lessThan(bundleRoleSortKey('drink')));
    expect(bundleRoleSortKey('drink'), lessThan(bundleRoleSortKey('extra')));
    expect(bundleRoleSortKey('unknown'), 99);
  });
}
