class WaitTimeAgg {
  final int count;
  final int medianMinutes;
  final int p90Minutes;
  final int lastDurationMinutes;

  const WaitTimeAgg({
    required this.count,
    required this.medianMinutes,
    required this.p90Minutes,
    required this.lastDurationMinutes,
  });

  factory WaitTimeAgg.fromJson(Map<String, dynamic> json) => WaitTimeAgg(
        count: (json['count'] as num?)?.toInt() ?? 0,
        medianMinutes: (json['medianMinutes'] as num?)?.toInt() ?? 0,
        p90Minutes: (json['p90Minutes'] as num?)?.toInt() ?? 0,
        lastDurationMinutes: (json['lastDurationMinutes'] as num?)?.toInt() ?? 0,
      );
}

class WaitTimeSummary {
  final String storeId;
  final String daypartKeyUsed;
  final int etaMinutes;
  final String source; // historical_median | historical_last | store_default
  final String method; // median | last | default
  final int medianMinutes;
  final int p90Minutes;
  final int lastDurationMinutes;
  final int count;
  final int sampleCount;
  final int defaultWaitMinutes;

  const WaitTimeSummary({
    required this.storeId,
    required this.daypartKeyUsed,
    required this.etaMinutes,
    required this.source,
    required this.method,
    required this.medianMinutes,
    required this.p90Minutes,
    required this.lastDurationMinutes,
    required this.count,
    required this.sampleCount,
    required this.defaultWaitMinutes,
  });

  factory WaitTimeSummary.fromJson(Map<String, dynamic> json) => WaitTimeSummary(
        storeId: (json['storeId'] as String?) ?? '',
        daypartKeyUsed: (json['daypartKeyUsed'] as String?) ?? '',
        etaMinutes: (json['etaMinutes'] as num?)?.toInt() ?? 0,
        source: (json['source'] as String?) ?? 'store_default',
        method: (json['method'] as String?) ?? 'default',
        medianMinutes: (json['medianMinutes'] as num?)?.toInt() ?? 0,
        p90Minutes: (json['p90Minutes'] as num?)?.toInt() ?? 0,
        lastDurationMinutes: (json['lastDurationMinutes'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
        sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
        defaultWaitMinutes: (json['defaultWaitMinutes'] as num?)?.toInt() ?? 0,
      );
}

class WaitTimeDailyPoint {
  final String date; // yyyy-mm-dd
  final DateTime? updatedAt;
  final WaitTimeAgg overall;
  final Map<String, WaitTimeAgg> dayparts;

  const WaitTimeDailyPoint({
    required this.date,
    required this.updatedAt,
    required this.overall,
    required this.dayparts,
  });

  factory WaitTimeDailyPoint.fromJson(Map<String, dynamic> json) {
    final rawDayparts = json['dayparts'];
    final dayparts = <String, WaitTimeAgg>{};
    if (rawDayparts is Map) {
      for (final entry in rawDayparts.entries) {
        final k = entry.key?.toString() ?? '';
        final v = entry.value;
        if (k.isEmpty) continue;
        if (v is Map<String, dynamic>) {
          dayparts[k] = WaitTimeAgg.fromJson(v);
        } else if (v is Map) {
          dayparts[k] = WaitTimeAgg.fromJson(v.cast<String, dynamic>());
        }
      }
    }
    return WaitTimeDailyPoint(
      date: (json['date'] as String?) ?? '',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      overall: WaitTimeAgg.fromJson(
        (json['overall'] is Map<String, dynamic>)
            ? json['overall'] as Map<String, dynamic>
            : (json['overall'] is Map)
                ? (json['overall'] as Map).cast<String, dynamic>()
                : const <String, dynamic>{},
      ),
      dayparts: dayparts,
    );
  }
}

class WaitTimeDailyResponse {
  final String storeId;
  final int days;
  final int defaultWaitMinutes;
  final List<WaitTimeDailyPoint> points;

  const WaitTimeDailyResponse({
    required this.storeId,
    required this.days,
    required this.defaultWaitMinutes,
    required this.points,
  });

  factory WaitTimeDailyResponse.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final points = (rawPoints is List ? rawPoints : const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(WaitTimeDailyPoint.fromJson)
        .toList(growable: false);
    return WaitTimeDailyResponse(
      storeId: (json['storeId'] as String?) ?? '',
      days: (json['days'] as num?)?.toInt() ?? 7,
      defaultWaitMinutes: (json['defaultWaitMinutes'] as num?)?.toInt() ?? 0,
      points: points,
    );
  }
}

