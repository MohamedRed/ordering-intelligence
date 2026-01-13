import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wait_time.dart';
import 'order_providers.dart';

final waitTimeSummaryProvider = FutureProvider<WaitTimeSummary>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.fetchWaitTimeSummary();
});

final waitTimeDailyProvider =
    FutureProvider.family<WaitTimeDailyResponse, int>((ref, days) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.fetchWaitTimeDaily(days: days);
});
