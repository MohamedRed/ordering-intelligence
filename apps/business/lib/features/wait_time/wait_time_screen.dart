import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/wait_time.dart';
import '../../providers/wait_time_providers.dart';
import '../../widgets/business_scaffold.dart';

enum _WaitTimeMode { overall, lunch, dinner }

class WaitTimeScreen extends ConsumerStatefulWidget {
  const WaitTimeScreen({super.key});

  @override
  ConsumerState<WaitTimeScreen> createState() => _WaitTimeScreenState();
}

class _WaitTimeScreenState extends ConsumerState<WaitTimeScreen> {
  _WaitTimeMode _mode = _WaitTimeMode.overall;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(waitTimeSummaryProvider);
    final dailyAsync = ref.watch(waitTimeDailyProvider(7));

    return BusinessScaffold(
      title: const Text('Wait time insights'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(waitTimeSummaryProvider);
            ref.invalidate(waitTimeDailyProvider(7));
          },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ShadCard(
            padding: const EdgeInsets.all(16),
            child: summaryAsync.when(
              loading: () => Row(
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Loading current ETA…')),
                ],
              ),
              error: (err, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Current ETA'),
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
              data: (summary) => _SummaryBody(summary: summary),
            ),
          ),
          const SizedBox(height: 16),
          ShadCard(
            padding: const EdgeInsets.all(16),
            child: dailyAsync.when(
              loading: () => Row(
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Loading 7-day trend…')),
                ],
              ),
              error: (err, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('7-day trend'),
                  const SizedBox(height: 6),
                  Text('Failed to load: $err',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  ShadButton.outline(
                    onPressed: () => ref.invalidate(waitTimeDailyProvider(7)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (daily) => _DailyBody(
                daily: daily,
                mode: _mode,
                onModeChanged: (m) => setState(() => _mode = m),
              ),
            ),
          ),
        ],
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
            _MetricChip(label: 'Samples', value: '${summary.sampleCount}'),
            if (summary.lastDurationMinutes > 0)
              _MetricChip(
                  label: 'Last', value: '${summary.lastDurationMinutes} min'),
            if (summary.medianMinutes > 0)
              _MetricChip(
                  label: 'Median', value: '${summary.medianMinutes} min'),
            if (summary.p90Minutes > 0)
              _MetricChip(label: 'p90', value: '${summary.p90Minutes} min'),
          ],
        ),
      ],
    );
  }

  String _sourceLabel(WaitTimeSummary s) {
    switch (s.source) {
      case 'historical_median':
        return 'Based on: historical median (${s.daypartKeyUsed.replaceAll('_', ' ')})';
      case 'historical_last':
        return 'Based on: last order (${s.daypartKeyUsed.replaceAll('_', ' ')})';
      case 'store_default':
      default:
        return 'Based on: store default';
    }
  }
}

class _DailyBody extends StatelessWidget {
  const _DailyBody({
    required this.daily,
    required this.mode,
    required this.onModeChanged,
  });

  final WaitTimeDailyResponse daily;
  final _WaitTimeMode mode;
  final ValueChanged<_WaitTimeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final series = _seriesForMode(daily.points, mode);
    final yMax = _maxY(series);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '7-day trend',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ToggleButtons(
              isSelected: [
                mode == _WaitTimeMode.overall,
                mode == _WaitTimeMode.lunch,
                mode == _WaitTimeMode.dinner,
              ],
              onPressed: (idx) {
                if (idx == 0) onModeChanged(_WaitTimeMode.overall);
                if (idx == 1) onModeChanged(_WaitTimeMode.lunch);
                if (idx == 2) onModeChanged(_WaitTimeMode.dinner);
              },
              children: const [
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('Overall')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('Lunch')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('Dinner')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: yMax,
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= daily.points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_shortDate(daily.points[idx].date),
                            style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: series.medianSpots,
                  isCurved: true,
                  barWidth: 3,
                  color: Colors.deepOrange,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: series.p90Spots,
                  isCurved: true,
                  barWidth: 2,
                  color: Colors.deepOrange.shade200,
                  dashArray: const [6, 6],
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: BarChart(
            BarChartData(
              minY: 0,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: series.countBars,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Last 7 days (numbers)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Median')),
              DataColumn(label: Text('p90')),
              DataColumn(label: Text('Count')),
            ],
            rows: [
              for (var i = 0; i < daily.points.length; i++)
                DataRow(
                  cells: [
                    DataCell(Text(_shortDate(daily.points[i].date))),
                    DataCell(Text(series.medians[i] > 0
                        ? '${series.medians[i]}'
                        : '—')),
                    DataCell(Text(series.p90s[i] > 0 ? '${series.p90s[i]}' : '—')),
                    DataCell(Text('${series.counts[i]}')),
                  ],
                )
            ],
          ),
        ),
      ],
    );
  }

  _Series _seriesForMode(List<WaitTimeDailyPoint> points, _WaitTimeMode mode) {
    final medians = <int>[];
    final p90s = <int>[];
    final counts = <int>[];
    final medianSpots = <FlSpot>[];
    final p90Spots = <FlSpot>[];
    final countBars = <BarChartGroupData>[];

    for (var i = 0; i < points.length; i++) {
      final agg = _aggForPoint(points[i], mode);
      medians.add(agg.medianMinutes);
      p90s.add(agg.p90Minutes);
      counts.add(agg.count);

      medianSpots.add(
        agg.count > 0 && agg.medianMinutes > 0
            ? FlSpot(i.toDouble(), agg.medianMinutes.toDouble())
            : FlSpot.nullSpot,
      );
      p90Spots.add(
        agg.count > 0 && agg.p90Minutes > 0
            ? FlSpot(i.toDouble(), agg.p90Minutes.toDouble())
            : FlSpot.nullSpot,
      );
      countBars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: agg.count.toDouble(),
              width: 10,
              borderRadius: BorderRadius.circular(4),
              color: Colors.blueGrey,
            ),
          ],
        ),
      );
    }

    return _Series(
      medians: medians,
      p90s: p90s,
      counts: counts,
      medianSpots: medianSpots,
      p90Spots: p90Spots,
      countBars: countBars,
    );
  }

  WaitTimeAgg _aggForPoint(WaitTimeDailyPoint p, _WaitTimeMode mode) {
    if (mode == _WaitTimeMode.overall) return p.overall;
    final parsed = DateTime.tryParse(p.date);
    if (parsed == null) return p.overall;
    final weekend = parsed.weekday == DateTime.saturday ||
        parsed.weekday == DateTime.sunday;
    final key = mode == _WaitTimeMode.lunch
        ? (weekend ? 'weekend_lunch' : 'weekday_lunch')
        : (weekend ? 'weekend_dinner' : 'weekday_dinner');
    return p.dayparts[key] ?? const WaitTimeAgg(count: 0, medianMinutes: 0, p90Minutes: 0, lastDurationMinutes: 0);
  }

  double _maxY(_Series s) {
    var maxV = 0;
    for (final v in s.p90s) {
      if (v > maxV) maxV = v;
    }
    for (final v in s.medians) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) return 30;
    // Add headroom.
    return (maxV + 5).toDouble();
  }

  String _shortDate(String date) {
    // yyyy-mm-dd → mm/dd
    if (date.length >= 10) {
      final mm = date.substring(5, 7);
      final dd = date.substring(8, 10);
      return '$mm/$dd';
    }
    return date;
  }
}

class _Series {
  final List<int> medians;
  final List<int> p90s;
  final List<int> counts;
  final List<FlSpot> medianSpots;
  final List<FlSpot> p90Spots;
  final List<BarChartGroupData> countBars;

  const _Series({
    required this.medians,
    required this.p90s,
    required this.counts,
    required this.medianSpots,
    required this.p90Spots,
    required this.countBars,
  });
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
