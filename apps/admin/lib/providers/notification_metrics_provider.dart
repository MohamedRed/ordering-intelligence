import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class NotificationMetrics {
  final int pushSent;
  final int smsSent;
  final int emailSent;
  final int pushFailed;
  final int smsFailed;
  final int emailFailed;

  const NotificationMetrics({
    required this.pushSent,
    required this.smsSent,
    required this.emailSent,
    required this.pushFailed,
    required this.smsFailed,
    required this.emailFailed,
  });
}

const _notificationUrl = String.fromEnvironment(
  'NOTIFICATION_SERVICE_URL',
  defaultValue: 'http://localhost:8084',
);

class NotificationMetricsApi {
  final http.Client _client;
  NotificationMetricsApi({http.Client? client}) : _client = client ?? http.Client();

  Future<NotificationMetrics> fetchMetrics() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_notificationUrl/metrics'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Metrics unavailable (${resp.statusCode})');
    }
    final body = resp.body;
    int get(String key) {
      final match = RegExp('$key\\s+(\\d+)').firstMatch(body);
      return match != null ? int.parse(match.group(1)!) : 0;
    }

    return NotificationMetrics(
      pushSent: get('notifications_push_sent_total'),
      smsSent: get('notifications_sms_sent_total'),
      emailSent: get('notifications_email_sent_total'),
      pushFailed: get('notifications_push_failed_total'),
      smsFailed: get('notifications_sms_failed_total'),
      emailFailed: get('notifications_email_failed_total'),
    );
  }

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }
}

final notificationMetricsApiProvider =
    Provider<NotificationMetricsApi>((ref) => NotificationMetricsApi());

final notificationMetricsProvider = FutureProvider<NotificationMetrics>((ref) async {
  final api = ref.watch(notificationMetricsApiProvider);
  return api.fetchMetrics();
});
