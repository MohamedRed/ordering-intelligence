import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/wait_time.dart';
import 'wait_time_metric_chip.dart';
import 'wait_time_state_views.dart';

class WaitTimeSummaryCard extends StatelessWidget {
  const WaitTimeSummaryCard({
    super.key,
    required this.summary,
    required this.onRetry,
  });

  final AsyncValue<WaitTimeSummary> summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: summary.when(
        loading: () =>
            const WaitTimeLoadingRow(message: 'Loading current ETA…'),
        error: (err, _) => WaitTimeErrorBlock(
          title: 'Current ETA',
          error: err,
          onRetry: onRetry,
        ),
        data: (summary) => _SummaryBody(summary: summary),
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final WaitTimeSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current quoted wait: about ${summary.etaMinutes} min',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          _sourceLabel(summary),
          style: TextStyle(color: Colors.grey[700]),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            WaitTimeMetricChip(
              label: 'Samples',
              value: '${summary.sampleCount}',
            ),
            if (summary.lastDurationMinutes > 0)
              WaitTimeMetricChip(
                label: 'Last',
                value: '${summary.lastDurationMinutes} min',
              ),
            if (summary.medianMinutes > 0)
              WaitTimeMetricChip(
                label: 'Median',
                value: '${summary.medianMinutes} min',
              ),
            if (summary.p90Minutes > 0)
              WaitTimeMetricChip(
                label: 'p90',
                value: '${summary.p90Minutes} min',
              ),
          ],
        ),
      ],
    );
  }

  String _sourceLabel(WaitTimeSummary summary) {
    final daypart = summary.daypartKeyUsed.replaceAll('_', ' ');
    switch (summary.source) {
      case 'historical_median':
        return 'Based on: historical median ($daypart)';
      case 'historical_last':
        return 'Based on: last order ($daypart)';
      case 'store_default':
      default:
        return 'Based on: store default';
    }
  }
}
