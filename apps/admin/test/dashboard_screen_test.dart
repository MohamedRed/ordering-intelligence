import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/features/dashboard/dashboard_screen.dart';
import 'package:admin_app/models/summary.dart';
import 'package:admin_app/providers/ingestion_badge_provider.dart';
import 'package:admin_app/providers/notification_metrics_provider.dart';
import 'package:admin_app/providers/summary_provider.dart';

import 'test_harness.dart';

void main() {
  testWidgets('dashboard displays key metrics', (tester) async {
    await tester.pumpWidget(
      adminTestApp(
        const DashboardScreen(),
        overrides: [
          orderSummaryProvider.overrideWith((ref) async => OrderSummary(
                total: 12,
                statusCounts: {'pending': 2, 'ready': 3},
                last24hCounts: {'completed': 7, 'cancelled': 1},
              )),
          notificationMetricsProvider.overrideWith(
            (ref) async => const NotificationMetrics(
              pushSent: 1,
              smsSent: 2,
              emailSent: 3,
              pushFailed: 0,
              smsFailed: 0,
              emailFailed: 1,
            ),
          ),
          ingestionBadgeProvider.overrideWith(
            (ref) async => const IngestionCounts(backlog: 4, dlq: 0),
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Orders (total)'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Notifications (push/sms/email)'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Notifications (push/sms/email)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Ingestion backlog / DLQ'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Ingestion backlog / DLQ'), findsOneWidget);
  });
}
