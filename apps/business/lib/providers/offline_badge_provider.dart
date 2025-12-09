import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_queue.dart';

final pendingStatusCountProvider = FutureProvider<int>((ref) async {
  final queue = StatusUpdateQueue();
  final items = await queue.load();
  return items.length;
});
