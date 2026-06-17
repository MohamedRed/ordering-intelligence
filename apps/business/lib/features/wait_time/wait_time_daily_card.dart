import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/wait_time.dart';
import 'wait_time_charts.dart';
import 'wait_time_daily_table.dart';
import 'wait_time_mode.dart';
import 'wait_time_series.dart';
import 'wait_time_state_views.dart';

class WaitTimeDailyCard extends StatelessWidget {
  const WaitTimeDailyCard({
    super.key,
    required this.daily,
    required this.mode,
    required this.onModeChanged,
    required this.onRetry,
  });

  final AsyncValue<WaitTimeDailyResponse> daily;
  final WaitTimeMode mode;
  final ValueChanged<WaitTimeMode> onModeChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: daily.when(
        loading: () =>
            const WaitTimeLoadingRow(message: 'Loading 7-day trend…'),
        error: (err, _) => WaitTimeErrorBlock(
          title: '7-day trend',
          error: err,
          onRetry: onRetry,
        ),
        data: (daily) => _DailyBody(
          daily: daily,
          mode: mode,
          onModeChanged: onModeChanged,
        ),
      ),
    );
  }
}

class _DailyBody extends StatelessWidget {
  const _DailyBody({
    required this.daily,
    required this.mode,
    required this.onModeChanged,
  });

  final WaitTimeDailyResponse daily;
  final WaitTimeMode mode;
  final ValueChanged<WaitTimeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final series = buildWaitTimeSeries(daily.points, mode);
    final yMax = maxWaitTimeY(series);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrendHeader(mode: mode, onModeChanged: onModeChanged),
        const SizedBox(height: 12),
        WaitTimeTrendChart(
          points: daily.points,
          series: series,
          maxY: yMax,
        ),
        const SizedBox(height: 12),
        WaitTimeVolumeChart(series: series),
        const SizedBox(height: 16),
        Text('Last 7 days (numbers)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        WaitTimeDailyTable(points: daily.points, series: series),
      ],
    );
  }
}

class _TrendHeader extends StatelessWidget {
  const _TrendHeader({
    required this.mode,
    required this.onModeChanged,
  });

  final WaitTimeMode mode;
  final ValueChanged<WaitTimeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('7-day trend', style: Theme.of(context).textTheme.titleMedium),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ToggleButtons(
            isSelected:
                WaitTimeMode.values.map((entry) => entry == mode).toList(),
            onPressed: (index) => onModeChanged(WaitTimeMode.values[index]),
            constraints: const BoxConstraints(minHeight: 36, minWidth: 74),
            children: [
              for (final entry in WaitTimeMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(entry.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
