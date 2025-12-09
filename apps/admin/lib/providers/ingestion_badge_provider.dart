import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class IngestionCounts {
  final int backlog;
  final int dlq;
  const IngestionCounts({required this.backlog, required this.dlq});
}

const _baseUrl = String.fromEnvironment('ADMIN_SERVICE_URL',
    defaultValue: 'http://localhost:8085');

class IngestionBadgeApi {
  final http.Client _client;
  final Future<String?> Function() _tokenSupplier;

  IngestionBadgeApi({http.Client? client, Future<String?> Function()? tokenSupplier})
      : _client = client ?? http.Client(),
        _tokenSupplier = tokenSupplier ?? _defaultTokenSupplier;

  Future<IngestionCounts> fetchCounts() async {
    final token = await _tokenSupplier();
    final resp = await _client.get(
      Uri.parse('$_baseUrl/ingest?counts=true&limit=1'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load ingestion counts: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return IngestionCounts(
      backlog: (data['backlog'] as num?)?.toInt() ?? 0,
      dlq: (data['dlq'] as num?)?.toInt() ?? 0,
    );
  }
}

Future<String?> _defaultTokenSupplier() async {
  final user = FirebaseAuth.instance.currentUser;
  return user?.getIdToken();
}

final ingestionBadgeApiProvider =
    Provider<IngestionBadgeApi>((ref) => IngestionBadgeApi());

final ingestionBadgeProvider = FutureProvider<IngestionCounts>((ref) async {
  final api = ref.watch(ingestionBadgeApiProvider);
  return api.fetchCounts();
});
