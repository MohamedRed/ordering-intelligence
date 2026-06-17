import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/group_orders/group_order_detail_formatters.dart';
import 'package:business_app/models/group_order.dart';

void main() {
  test('group order detail formatters preserve existing display values', () {
    expect(formatGroupOrderCents(0), '—');
    expect(formatGroupOrderCents(1299), r'$12.99');
    expect(
        formatGroupOrderDate(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');

    final orderWithCode = GroupOrder.fromJson({
      'id': 'group-1',
      'joinCode': 'ABC123',
    });
    final orderWithoutCode = GroupOrder.fromJson({
      'id': 'group-2',
    });

    expect(joinCodeForGroupOrder(orderWithCode), 'ABC123');
    expect(joinCodeForGroupOrder(orderWithoutCode), 'group-2');
  });
}
