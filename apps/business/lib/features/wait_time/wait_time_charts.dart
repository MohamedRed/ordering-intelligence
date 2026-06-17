import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/wait_time.dart';
import 'wait_time_series.dart';

class WaitTimeTrendChart extends StatelessWidget {
  const WaitTimeTrendChart({
    super.key,
    required this.points,
    required this.series,
    required this.maxY,
  });

  final List<WaitTimeDailyPoint> points;
  final WaitTimeSeries series;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      shortWaitTimeDate(points[index].date),
                      style: const TextStyle(fontSize: 10),
                    ),
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
    );
  }
}

class WaitTimeVolumeChart extends StatelessWidget {
  const WaitTimeVolumeChart({super.key, required this.series});

  final WaitTimeSeries series;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}
