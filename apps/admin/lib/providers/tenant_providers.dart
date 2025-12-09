import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/tenant.dart';

const _baseUrl = String.fromEnvironment('ADMIN_SERVICE_URL',
    defaultValue: 'http://localhost:8085');

class TenantApi {
  final http.Client _client;
  TenantApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Tenant>> listTenants() async {
    final token = await _token();
    final resp = await _client.get(Uri.parse('$_baseUrl/tenants'),
        headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load tenants: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Tenant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, int>> fetchIngestionCounts() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_baseUrl/ingest?counts=true&limit=5'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load ingestion counts: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return {
      'backlog': (data['backlog'] as num?)?.toInt() ?? 0,
      'dlq': (data['dlq'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> updateFlags(String tenantId, Map<String, bool> flags) async {
    final token = await _token();
    final resp = await _client.patch(
      Uri.parse('$_baseUrl/tenants/$tenantId/feature-flags'),
      headers: _headers(token),
      body: jsonEncode(flags),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update flags: ${resp.statusCode}');
    }
  }

  Future<Tenant> createTenant({
    required String name,
    required String primaryUser,
    required String storeId,
    required String businessType,
    String status = 'active',
    String timezone = '',
    String phone = '',
    Map<String, bool>? featureFlags,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_baseUrl/tenants'),
      headers: _headers(token),
      body: jsonEncode({
        'name': name,
        'primaryUser': primaryUser,
        'storeId': storeId,
        'businessType': businessType,
        'status': status,
        'timezone': timezone,
        'phone': phone,
        'featureFlags': featureFlags ?? {},
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to create tenant: ${resp.statusCode}');
    }
    return Tenant.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Map<String, String> _headers(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }
}

final tenantApiProvider = Provider<TenantApi>((ref) => TenantApi());

final tenantsProvider = FutureProvider<List<Tenant>>((ref) async {
  final api = ref.watch(tenantApiProvider);
  return api.listTenants();
});
