import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal offline queue for order status updates.
class StatusUpdateQueue {
  static const _key = 'pending_status_updates';

  Future<void> flush(Function(QueuedStatus) handler) async {
    final pending = await load();
    if (pending.isEmpty) return;
    final still = <QueuedStatus>[];
    for (final item in pending) {
      try {
        await handler(item);
      } catch (_) {
        still.add(item);
      }
    }
    await replaceAll(still);
  }

  /// Fire-and-forget periodic flush; caller can schedule (e.g., on app resume).
  Future<void> flushIfAny(Function(QueuedStatus) handler) async {
    final pending = await load();
    if (pending.isEmpty) return;
    await flush(handler);
  }

  Future<List<QueuedStatus>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map(
            (e) => QueuedStatus.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(QueuedStatus update) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? [];
    current.add(jsonEncode(update.toJson()));
    await prefs.setStringList(_key, current);
  }

  Future<void> replaceAll(List<QueuedStatus> updates) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = updates.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_key, serialized);
  }
}

class QueuedStatus {
  final String orderId;
  final String status;

  QueuedStatus({required this.orderId, required this.status});

  Map<String, dynamic> toJson() => {'orderId': orderId, 'status': status};

  factory QueuedStatus.fromJson(Map<String, dynamic> json) => QueuedStatus(
        orderId: json['orderId'] as String,
        status: json['status'] as String,
      );
}
