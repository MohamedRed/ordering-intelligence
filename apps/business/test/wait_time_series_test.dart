import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/wait_time/wait_time_mode.dart';
import 'package:business_app/features/wait_time/wait_time_series.dart';
import 'package:business_app/models/wait_time.dart';

void main() {
  test('wait time series selects daypart aggregates and derives chart bounds',
      () {
    final weekday = WaitTimeDailyPoint(
      date: '2026-06-17',
      updatedAt: null,
      overall: const WaitTimeAgg(
        count: 8,
        medianMinutes: 16,
        p90Minutes: 24,
        lastDurationMinutes: 14,
      ),
      dayparts: {
        'weekday_lunch': const WaitTimeAgg(
          count: 4,
          medianMinutes: 12,
          p90Minutes: 18,
          lastDurationMinutes: 11,
        ),
        'weekday_dinner': const WaitTimeAgg(
          count: 6,
          medianMinutes: 20,
          p90Minutes: 30,
          lastDurationMinutes: 19,
        ),
      },
    );
    final weekend = WaitTimeDailyPoint(
      date: '2026-06-14',
      updatedAt: null,
      overall: const WaitTimeAgg(
        count: 10,
        medianMinutes: 22,
        p90Minutes: 32,
        lastDurationMinutes: 21,
      ),
      dayparts: {
        'weekend_lunch': const WaitTimeAgg(
          count: 5,
          medianMinutes: 15,
          p90Minutes: 26,
          lastDurationMinutes: 14,
        ),
        'weekend_dinner': const WaitTimeAgg(
          count: 7,
          medianMinutes: 28,
          p90Minutes: 40,
          lastDurationMinutes: 27,
        ),
      },
    );

    expect(
      aggregateForWaitTimeMode(weekday, WaitTimeMode.lunch).medianMinutes,
      12,
    );
    expect(
      aggregateForWaitTimeMode(weekend, WaitTimeMode.dinner).medianMinutes,
      28,
    );

    final series = buildWaitTimeSeries(
      [weekday, weekend],
      WaitTimeMode.dinner,
    );

    expect(series.medians, [20, 28]);
    expect(series.p90s, [30, 40]);
    expect(series.counts, [6, 7]);
    expect(series.medianSpots.first.y, 20);
    expect(series.countBars.last.barRods.single.toY, 7);
    expect(maxWaitTimeY(series), 45);
    expect(shortWaitTimeDate('2026-06-17'), '06/17');
  });
}
