import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/summary_provider.dart';
import '../../providers/notification_metrics_provider.dart';
import '../../providers/ingestion_badge_provider.dart';
import '../../widgets/admin_navigation_drawer.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(orderSummaryProvider);
    final notifMetricsAsync = ref.watch(notificationMetricsProvider);
    final ingestAsync = ref.watch(ingestionBadgeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Operator Dashboard')),
      drawer: const AdminNavigationDrawer(),
      body: summaryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load summary: $err')),
        data: (summary) {
          final status = summary.statusCounts;
          final width = MediaQuery.of(context).size.width;
          final columns = width > 1100
              ? 3
              : width > 720
                  ? 2
                  : 1;
          final cards = <Widget>[
            _MetricCard(title: 'Orders (total)', value: '${summary.total}'),
            _MetricCard(title: 'Pending', value: '${status['pending'] ?? 0}'),
            _MetricCard(title: 'Ready', value: '${status['ready'] ?? 0}'),
            _MetricCard(
                title: 'Completed (24h)',
                value: '${summary.last24hCounts['completed'] ?? 0}'),
            _MetricCard(
                title: 'Cancelled (24h)',
                value: '${summary.last24hCounts['cancelled'] ?? 0}'),
            notifMetricsAsync.when(
              loading: () => const _MetricCard(title: 'Notifications', value: '…'),
              error: (err, _) =>
                  _MetricCard(title: 'Notifications', value: 'err: $err'),
              data: (metrics) => _MetricCard(
                title: 'Notifications (push/sms/email)',
                value:
                    '${metrics.pushSent}/${metrics.smsSent}/${metrics.emailSent}\nfail ${metrics.pushFailed}/${metrics.smsFailed}/${metrics.emailFailed}',
              ),
            ),
            ingestAsync.when(
              loading: () => const _MetricCard(title: 'Ingestion', value: '…'),
              error: (err, _) => _MetricCard(title: 'Ingestion', value: 'err: $err'),
              data: (c) => _MetricCard(
                title: 'Ingestion backlog / DLQ',
                value: '${c.backlog} / ${c.dlq}',
                highlight: c.dlq > 0,
              ),
            ),
          ];
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: cards,
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, this.highlight = false});

  final String title;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(color: highlight ? Colors.red.shade700 : Colors.blueGrey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
