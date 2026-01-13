import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../models/wait_time.dart';
import '../../../providers/wait_time_providers.dart';

class OrderWaitTimeDashboardCard extends ConsumerWidget {
  const OrderWaitTimeDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(waitTimeSummaryProvider);
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: summaryAsync.when(
        loading: () => const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading wait time…')),
          ],
        ),
        error: (err, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wait time'),
            const SizedBox(height: 6),
            Text('Failed to load: $err',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            ShadButton.outline(
              onPressed: () => ref.invalidate(waitTimeSummaryProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
        data: (summary) {
          final subtitle = _waitTimeSourceLabel(summary);
          final samples = summary.sampleCount;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Current quoted wait: about ${summary.etaMinutes} min',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ShadButton.outline(
                    onPressed: () => context.push('/wait-time'),
                    child: const Text('View details'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _MetricChip(
                    label: 'Samples',
                    value: '$samples',
                  ),
                  if (summary.lastDurationMinutes > 0)
                    _MetricChip(
                      label: 'Last',
                      value: '${summary.lastDurationMinutes} min',
                    ),
                  if (summary.medianMinutes > 0)
                    _MetricChip(
                      label: 'Median',
                      value: '${summary.medianMinutes} min',
                    ),
                  if (summary.p90Minutes > 0)
                    _MetricChip(
                      label: 'p90',
                      value: '${summary.p90Minutes} min',
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _waitTimeSourceLabel(WaitTimeSummary summary) {
    switch (summary.source) {
      case 'historical_median':
        return 'Based on: historical median (${summary.daypartKeyUsed.replaceAll('_', ' ')})';
      case 'historical_last':
        return 'Based on: last order (${summary.daypartKeyUsed.replaceAll('_', ' ')})';
      case 'store_default':
      default:
        return 'Based on: store default';
    }
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text('$label: $value'),
    );
  }
}
