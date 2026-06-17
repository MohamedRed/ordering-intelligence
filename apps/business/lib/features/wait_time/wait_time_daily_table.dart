import 'package:flutter/material.dart';

import '../../models/wait_time.dart';
import 'wait_time_series.dart';

class WaitTimeDailyTable extends StatelessWidget {
  const WaitTimeDailyTable({
    super.key,
    required this.points,
    required this.series,
  });

  final List<WaitTimeDailyPoint> points;
  final WaitTimeSeries series;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Median')),
          DataColumn(label: Text('p90')),
          DataColumn(label: Text('Count')),
        ],
        rows: [
          for (var i = 0; i < points.length; i++)
            DataRow(
              cells: [
                DataCell(Text(shortWaitTimeDate(points[i].date))),
                DataCell(
                    Text(series.medians[i] > 0 ? '${series.medians[i]}' : '—')),
                DataCell(Text(series.p90s[i] > 0 ? '${series.p90s[i]}' : '—')),
                DataCell(Text('${series.counts[i]}')),
              ],
            ),
        ],
      ),
    );
  }
}
