import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/wait_time.dart';
import 'wait_time_mode.dart';

class WaitTimeSeries {
  const WaitTimeSeries({
    required this.medians,
    required this.p90s,
    required this.counts,
    required this.medianSpots,
    required this.p90Spots,
    required this.countBars,
  });

  final List<int> medians;
  final List<int> p90s;
  final List<int> counts;
  final List<FlSpot> medianSpots;
  final List<FlSpot> p90Spots;
  final List<BarChartGroupData> countBars;
}

WaitTimeSeries buildWaitTimeSeries(
  List<WaitTimeDailyPoint> points,
  WaitTimeMode mode,
) {
  final medians = <int>[];
  final p90s = <int>[];
  final counts = <int>[];
  final medianSpots = <FlSpot>[];
  final p90Spots = <FlSpot>[];
  final countBars = <BarChartGroupData>[];

  for (var i = 0; i < points.length; i++) {
    final agg = aggregateForWaitTimeMode(points[i], mode);
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

  return WaitTimeSeries(
    medians: medians,
    p90s: p90s,
    counts: counts,
    medianSpots: medianSpots,
    p90Spots: p90Spots,
    countBars: countBars,
  );
}

WaitTimeAgg aggregateForWaitTimeMode(
  WaitTimeDailyPoint point,
  WaitTimeMode mode,
) {
  if (mode == WaitTimeMode.overall) return point.overall;
  final parsed = DateTime.tryParse(point.date);
  if (parsed == null) return point.overall;

  final weekend =
      parsed.weekday == DateTime.saturday || parsed.weekday == DateTime.sunday;
  final key = mode == WaitTimeMode.lunch
      ? (weekend ? 'weekend_lunch' : 'weekday_lunch')
      : (weekend ? 'weekend_dinner' : 'weekday_dinner');
  return point.dayparts[key] ??
      const WaitTimeAgg(
        count: 0,
        medianMinutes: 0,
        p90Minutes: 0,
        lastDurationMinutes: 0,
      );
}

double maxWaitTimeY(WaitTimeSeries series) {
  var maxValue = 0;
  for (final value in series.p90s) {
    if (value > maxValue) maxValue = value;
  }
  for (final value in series.medians) {
    if (value > maxValue) maxValue = value;
  }
  if (maxValue <= 0) return 30;
  return (maxValue + 5).toDouble();
}

String shortWaitTimeDate(String date) {
  if (date.length >= 10) {
    final mm = date.substring(5, 7);
    final dd = date.substring(8, 10);
    return '$mm/$dd';
  }
  return date;
}
