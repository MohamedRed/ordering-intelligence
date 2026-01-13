import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/orders/order_list_screen.dart';

void main() {
  testWidgets('order list shows latest orders', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: OrderListScreen()),
      ),
    );

    expect(find.textContaining('Large Pepperoni'), findsOneWidget);
    expect(find.textContaining('Awaiting confirmation'), findsOneWidget);
  }, skip: true);
}
