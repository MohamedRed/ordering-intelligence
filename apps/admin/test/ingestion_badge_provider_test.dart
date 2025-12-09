import 'dart:convert';

import 'package:admin_app/providers/ingestion_badge_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  group('IngestionBadgeApi', () {
    test('parses backlog/dlq counts and passes auth header', () async {
      String? authHeader;
      final client = MockClient((req) async {
        authHeader = req.headers['Authorization'];
        return http.Response(jsonEncode({'backlog': 3, 'dlq': 1}), 200);
      });

      final api = IngestionBadgeApi(
        client: client,
        tokenSupplier: () async => 'test-token',
      );

      final counts = await api.fetchCounts();
      expect(counts.backlog, 3);
      expect(counts.dlq, 1);
      expect(authHeader, 'Bearer test-token');
    });

    test('throws when non-200 returned', () async {
      final client = MockClient((req) async => http.Response('nope', 500));
      final api = IngestionBadgeApi(client: client, tokenSupplier: () async => null);
      expect(api.fetchCounts(), throwsException);
    });
  });
}
