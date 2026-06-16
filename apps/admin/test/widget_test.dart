import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/features/dashboard/dashboard_screen.dart';
import 'package:admin_app/models/summary.dart';
import 'package:admin_app/providers/ingestion_badge_provider.dart';
import 'package:admin_app/providers/notification_metrics_provider.dart';
import 'package:admin_app/providers/summary_provider.dart';

import 'test_harness.dart';

void main() {
  testWidgets('admin dashboard shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      adminTestApp(
        const DashboardScreen(),
        overrides: [
          orderSummaryProvider.overrideWith((ref) async => OrderSummary(
                total: 1,
                statusCounts: const {},
                last24hCounts: const {},
              )),
          notificationMetricsProvider.overrideWith(
            (ref) async => const NotificationMetrics(
              pushSent: 0,
              smsSent: 0,
              emailSent: 0,
              pushFailed: 0,
              smsFailed: 0,
              emailFailed: 0,
            ),
          ),
          ingestionBadgeProvider.overrideWith(
            (ref) async => const IngestionCounts(backlog: 0, dlq: 0),
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Operator Dashboard'), findsOneWidget);
    expect(find.text('Orders (total)'), findsOneWidget);
  });
}
