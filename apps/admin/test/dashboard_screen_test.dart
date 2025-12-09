import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/features/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('dashboard displays key metrics', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DashboardScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Active Tenants'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('AI Order Completion'), 300);
    expect(find.text('AI Order Completion'), findsOneWidget);
  });
}
