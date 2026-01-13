import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../util/store_id.dart';

const _dispatchBaseUrl = String.fromEnvironment(
  'DISPATCH_SERVICE_URL',
  defaultValue: 'https://dispatch-service-230152279015.us-central1.run.app',
);

class DispatchDriver {
  final String id;
  final String displayName;
  final String phoneE164;
  final bool active;
  final int maxActiveStops;
  final String uid;

  const DispatchDriver({
    required this.id,
    required this.displayName,
    required this.phoneE164,
    required this.active,
    required this.maxActiveStops,
    required this.uid,
  });

  factory DispatchDriver.fromJson(String id, Map<String, dynamic> data) {
    return DispatchDriver(
      id: id,
      displayName: (data['displayName'] as String?)?.trim() ?? '',
      phoneE164: (data['phoneE164'] as String?)?.trim() ?? '',
      active: data['active'] == true,
      maxActiveStops: (data['maxActiveStops'] is num)
          ? (data['maxActiveStops'] as num).toInt()
          : 3,
      uid: (data['uid'] as String?)?.trim() ?? '',
    );
  }
}

class DispatchApi {
  final http.Client _client;
  DispatchApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse(_dispatchBaseUrl + path);

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Failed to fetch auth token');
    }
    return token;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<List<DispatchDriver>> listDrivers() async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final resp = await _client.get(
      _uri('/v1/stores/$storeId/drivers/'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to load drivers: ${resp.statusCode} ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    final drivers = (decoded is Map && decoded['drivers'] is List)
        ? decoded['drivers'] as List
        : const <dynamic>[];
    return drivers
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map((e) {
          final id = (e['id'] as String?)?.trim() ?? '';
          final data = (e['data'] is Map)
              ? (e['data'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          return DispatchDriver.fromJson(id, data);
        })
        .where((d) => d.id.isNotEmpty)
        .toList();
  }

  Future<void> createDriver({
    required String displayName,
    required String phoneE164,
    int maxActiveStops = 3,
  }) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/drivers/'),
      headers: _headers(token),
      body: jsonEncode({
        'displayName': displayName.trim(),
        'phoneE164': phoneE164.trim(),
        'maxActiveStops': maxActiveStops,
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception(
          'Failed to create driver: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> setDriverActive(String driverId, bool active) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final resp = await _client.patch(
      _uri('/v1/stores/$storeId/drivers/$driverId'),
      headers: _headers(token),
      body: jsonEncode({'active': active}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to update driver: ${resp.statusCode} ${resp.body}');
    }
  }
}
