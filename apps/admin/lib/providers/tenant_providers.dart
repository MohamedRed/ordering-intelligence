import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';

import '../models/tenant.dart';

const _uploadBaseUrlRaw = String.fromEnvironment(
  'UPLOAD_BASE_URL',
  // Hard-coded default to the deployed onboarding service. Override with
  // --dart-define=UPLOAD_BASE_URL=... if needed.
  defaultValue: 'https://onboarding-service-230152279015.us-central1.run.app',
);
// For the new onboarding service we use the same base as uploads.
const _onboardingBaseUrl = _uploadBaseUrlRaw;

// Menu ingestion service (used for approving/publishing the produced menu draft).
const _menuIngestionBaseUrl = String.fromEnvironment(
  'MENU_INGESTION_BASE_URL',
  defaultValue: 'https://menu-ingestion-230152279015.us-central1.run.app',
);

// Order service (used to verify agent-facing menu snapshots after publishing).
const _orderServiceBaseUrl = String.fromEnvironment(
  'ORDER_SERVICE_URL',
  defaultValue: 'https://order-service-230152279015.us-central1.run.app',
);
// Legacy admin-service (tenants list/feature flags)
const _adminBaseUrl = String.fromEnvironment(
  'ADMIN_BASE_URL',
  defaultValue: 'https://admin-service-230152279015.us-central1.run.app',
);

class TenantApi {
  final http.Client _client;
  TenantApi({http.Client? client}) : _client = client ?? http.Client();

  // --- Onboarding-service session APIs ---
  Future<String> startSession({String? tenantId, String? storeId}) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/onboarding-sessions'),
      headers: _headers(token),
      body: jsonEncode({
        if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
        if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to start session (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['session_id'] as String;
  }

  Future<void> attachFlyers(String sessionId, List<String> urls) async {
    if (urls.isEmpty) return;
    final token = await _token();
    final resp = await _client.patch(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/menu-flyers'),
      headers: _headers(token),
      body: jsonEncode({'urls': urls}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Attach flyers failed (${resp.statusCode})');
    }
  }

  Future<void> detachFlyers(String sessionId, List<String> urls) async {
    if (urls.isEmpty) return;
    final token = await _token();
    final resp = await _client.delete(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/menu-flyers'),
      headers: _headers(token),
      body: jsonEncode({'urls': urls}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Detach flyers failed (${resp.statusCode})');
    }
  }

  Future<Map<String, dynamic>> prefill(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/onboarding-sessions/$sessionId/prefill'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Prefill failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> updateBusiness({
    required String sessionId,
    String? name,
    String? primaryUser,
    required String storeId,
    required String businessType,
    String? timezone,
    String? phone,
    required String country,
    String? currency,
    int? fuelDefaultPrepayCents,
  }) async {
    final token = await _token();
    final resp = await _client.patch(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/business-details'),
      headers: _headers(token),
      body: jsonEncode({
        if (name != null && name.isNotEmpty) 'name': name,
        if (primaryUser != null && primaryUser.isNotEmpty)
          'primary_user': primaryUser,
        'store_id': storeId,
        'type': businessType,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'country': country,
        if (currency != null && currency.isNotEmpty) 'currency': currency,
        if (fuelDefaultPrepayCents != null && fuelDefaultPrepayCents > 0)
          'fuel_default_prepay_cents': fuelDefaultPrepayCents,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Business update failed (${resp.statusCode})');
    }
  }

  Future<String?> triggerIngest(String sessionId,
      {String mode = 'menu_only'}) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/ingest-menu'),
      headers: _headers(token),
      body: jsonEncode({'mode': mode}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Ingest trigger failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['job_id'] as String?;
  }

  Future<String?> resumeIngestImages(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/ingest-menu/resume-images'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Resume images failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['job_id'] as String?;
  }

  Future<Map<String, dynamic>> syncIngest(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/sync-ingest'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Ingest sync failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> ingestWorkflow(String sessionId,
      {int limit = 600}) async {
    final token = await _token();
    final uri = Uri.parse(
            '$_onboardingBaseUrl/onboarding-sessions/$sessionId/ingest-workflow')
        .replace(queryParameters: {'limit': '$limit'});
    final resp = await _client.get(
      uri,
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Ingest workflow failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelIngest(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/cancel-ingest'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Cancel ingest failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Publish the ingestion draft into the canonical menu documents used by agents:
  /// - Firestore `menus/{storeId}` (order-service reads this for /menu/snapshot)
  /// - Firestore `restaurants/{storeId}/menus/*` (human-viewable copy)
  Future<void> approveIngestJob(String jobId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_menuIngestionBaseUrl/ingest/$jobId/approve'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Menu publish failed (${resp.statusCode}): ${resp.body}');
    }
  }

  /// Fetch the agent-facing menu snapshot from order-service.
  /// Returns null when no menu exists for this store yet.
  Future<Map<String, dynamic>?> getOrderServiceMenuSnapshot(
      {required String storeId}) async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse(
          '$_orderServiceBaseUrl/stores/${Uri.encodeComponent(storeId)}/menu/snapshot'),
      headers: _headers(token),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception(
          'Snapshot fetch failed (${resp.statusCode}): ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<String> createAgent(String sessionId, {String? name}) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse(
          '$_onboardingBaseUrl/onboarding-sessions/$sessionId/create-agent'),
      headers: _headers(token),
      body: jsonEncode({
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Create agent failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = data['agent_id'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('Create agent response missing agent_id');
    }
    return id;
  }

  Future<void> finalize(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/onboarding-sessions/$sessionId/finalize'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Finalize failed (${resp.statusCode})');
    }
  }

  // Stripe Connect helpers
  Future<String> createStripeAccount(String sessionId,
      {String businessType = 'company'}) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/stripe/account'),
      headers: _headers(token),
      body: jsonEncode({
        'session_id': sessionId,
        'business_type': businessType,
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('Stripe account failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['account_id'] as String;
  }

  Future<String> createStripeAccountSession(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/stripe/account-session'),
      headers: _headers(token),
      body: jsonEncode({'session_id': sessionId}),
    );
    if (resp.statusCode != 201) {
      throw Exception('Stripe account-session failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['client_secret'] as String;
  }

  Future<String> createStripeAccountLink(String sessionId) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_onboardingBaseUrl/stripe/account-link'),
      headers: _headers(token),
      body: jsonEncode({
        'session_id': sessionId,
        'refresh_url': 'https://admin.onboarding/stripe/refresh',
        'return_url': 'https://admin.onboarding/stripe/return',
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('Stripe account-link failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  // (Optional) status fetch
  Future<Map<String, dynamic>> status(String sessionId) async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_onboardingBaseUrl/onboarding-sessions/$sessionId/status'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Status fetch failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> tenantOnboarding(String tenantId) async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_onboardingBaseUrl/onboarding-tenants/$tenantId'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Tenant onboarding fetch failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // ---- Legacy admin-service APIs (still used by tenant list screen) ----
  Future<List<Tenant>> listTenants() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_adminBaseUrl/tenants'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load tenants (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Tenant.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateFlags(String tenantId, Map<String, bool> flags) async {
    final token = await _token();
    final resp = await _client.patch(
      Uri.parse('$_adminBaseUrl/tenants/$tenantId/feature-flags'),
      headers: _headers(token),
      body: jsonEncode(flags),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update flags (${resp.statusCode})');
    }
  }

  /// Demo helper: route an ElevenLabs agent (web widget) to a tenant/store for conversation-init variables.
  Future<void> setDemoAgentRoute({
    required String agentId,
    required String tenantId,
    required String storeId,
    required String businessType,
    String? environment,
    String? demoSessionId,
    String? demoCallerId,
    String? demoCallSid,
    String? demoCustomerName,
    bool? demoIsReturningCustomer,
    List<String>? demoTopReorders,
    int? demoEtaMinutes,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_adminBaseUrl/demo/agent-route'),
      headers: _headers(token),
      body: jsonEncode({
        'agentId': agentId,
        'tenantId': tenantId,
        'storeId': storeId,
        'businessType': businessType,
        if (environment != null) 'environment': environment,
        if (demoSessionId != null) 'demoSessionId': demoSessionId,
        if (demoCallerId != null && demoCallerId.trim().isNotEmpty)
          'demoCallerId': demoCallerId.trim(),
        if (demoCallSid != null && demoCallSid.trim().isNotEmpty)
          'demoCallSid': demoCallSid.trim(),
        if (demoCustomerName != null && demoCustomerName.trim().isNotEmpty)
          'demoCustomerName': demoCustomerName.trim(),
        if (demoIsReturningCustomer != null)
          'demoIsReturningCustomer': demoIsReturningCustomer,
        if (demoTopReorders != null && demoTopReorders.isNotEmpty)
          'demoTopReorders': demoTopReorders,
        if (demoEtaMinutes != null && demoEtaMinutes > 0)
          'demoEtaMinutes': demoEtaMinutes,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to set demo route (${resp.statusCode}): ${resp.body}');
    }
  }

  /// Demo helper: fetch the current agent route and the last conversation-init variables observed by agent-webhooks.
  Future<Map<String, dynamic>> getDemoAgentRouteStatus(
      {required String agentId}) async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse(
          '$_adminBaseUrl/demo/agent-route/${Uri.encodeComponent(agentId)}'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to fetch demo route status (${resp.statusCode}): ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Tenant> createTenant({
    required String name,
    required String primaryUser,
    required String storeId,
    required String businessType,
    String status = 'pending',
    Map<String, bool>? featureFlags,
    String? timezone,
    String? phone,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_adminBaseUrl/tenants'),
      headers: _headers(token),
      body: jsonEncode({
        'name': name,
        'primaryUser': primaryUser,
        'status': status,
        'featureFlags': featureFlags ?? {},
        'storeId': storeId,
        'businessType': businessType,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }),
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to create tenant (${resp.statusCode})');
    }
    return Tenant.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Uploads a flyer file and returns url/key.
  Future<Map<String, String>> uploadFlyer(PlatformFile file) async {
    final token = await _token();
    final uri = _buildUploadUri();
    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final ext = (file.extension ?? '').toLowerCase();
    MediaType? mediaType;
    if (ext == 'jpg' || ext == 'jpeg') mediaType = MediaType('image', 'jpeg');
    if (ext == 'png') mediaType = MediaType('image', 'png');
    if (ext == 'webp') mediaType = MediaType('image', 'webp');
    if (ext == 'pdf') mediaType = MediaType('application', 'pdf');

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      file.bytes ?? [],
      filename: file.name,
      contentType: mediaType,
    ));
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Flyer upload failed (${resp.statusCode})');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = data['url'] as String?;
    final key = data['key'] as String?;
    if (url == null || url.isEmpty || key == null || key.isEmpty) {
      throw Exception('Flyer upload response missing url/key');
    }
    return {'url': url, 'key': key};
  }

  Future<void> deleteFlyer(String key) async {
    final token = await _token();
    final uri = _buildUploadUri(); // same base, DELETE with key
    final resp = await http.delete(
      uri,
      headers: _headers(token),
      body: jsonEncode({'key': key}),
    );
    if (resp.statusCode != 204) {
      throw Exception('Failed to delete flyer (${resp.statusCode})');
    }
  }

  Uri _buildUploadUri() {
    return Uri.parse(_uploadBaseUrlRaw).replace(path: '/uploads/menu-flyer');
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
