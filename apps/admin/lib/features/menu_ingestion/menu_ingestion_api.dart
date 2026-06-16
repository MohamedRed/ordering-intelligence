import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'menu_ingestion_models.dart';

const menuIngestionBaseUrl = String.fromEnvironment(
  'MENU_INGESTION_BASE_URL',
  defaultValue: 'https://menu-ingestion-230152279015.us-central1.run.app',
);

class MenuIngestionApi {
  MenuIngestionApi({
    http.Client? client,
    FirebaseAuth? auth,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _auth = auth ?? FirebaseAuth.instance,
        _baseUrl = (baseUrl ?? menuIngestionBaseUrl).replaceFirst(
          RegExp(r'/$'),
          '',
        );

  final http.Client _client;
  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<List<MenuJob>> fetchJobs({int limit = 25}) async {
    final resp = await _client.get(
      _uri('/ingest?limit=$limit'),
      headers: await _authHeaders(),
    );
    _ensureOk(resp, 'Failed to load jobs');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((data['jobs'] ?? const []) as List)
        .map((job) => MenuJob.fromJson(Map<String, dynamic>.from(job as Map)))
        .toList();
  }

  Future<DraftDetail> loadDraft(String jobId) async {
    final resp = await _client.get(
      _uri('/ingest/$jobId/draft'),
      headers: await _authHeaders(),
    );
    _ensureOk(resp, 'Draft load failed');
    return DraftDetail.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> approve(String jobId) async {
    final resp = await _client.post(
      _uri('/ingest/$jobId/approve'),
      headers: await _authHeaders(),
    );
    _ensureOk(resp, 'Approve failed');
  }

  Future<List<AgentJob>> loadAgentJobs() async {
    final resp = await _client.get(
      _uri('/agent-jobs'),
      headers: await _authHeaders(),
    );
    _ensureOk(resp, 'Failed to load agent jobs');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((data['jobs'] ?? const []) as List)
        .map((job) => AgentJob.fromJson(Map<String, dynamic>.from(job as Map)))
        .toList();
  }

  Future<bool> loadAgentEnabled() async {
    final resp = await _client.get(
      _uri('/agent-worker/config'),
      headers: await _authHeaders(),
    );
    _ensureOk(resp, 'Failed to load agent worker config');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['enabled'] as bool? ?? false;
  }

  Future<void> setAgentEnabled(bool enabled) async {
    final resp = await _client.post(
      _uri('/agent-worker/config'),
      headers: await _authHeaders(),
      body: jsonEncode({'enabled': enabled}),
    );
    _ensureOk(resp, 'Failed to update agent worker config');
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, String>> _authHeaders() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _ensureOk(http.Response resp, String message) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('$message (${resp.statusCode})');
    }
  }
}
