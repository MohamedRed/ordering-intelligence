import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/delivery_partner_compliance.dart';
import '../models/delivery_partner_stripe_status.dart';

const onboardingBaseUrl = String.fromEnvironment(
  'ONBOARDING_SERVICE_URL',
  defaultValue: 'https://dev-onboarding-service.liive.app',
);

class DeliveryPartnerOnboardingApi {
  DeliveryPartnerOnboardingApi({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse(onboardingBaseUrl + path);

  Future<String> _delivererId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');
    return user.uid;
  }

  Future<DeliveryPartnerStripeStatus?> fetchStripeStatus() async {
    final delivererId = await _delivererId();
    final resp = await _client.get(
      _uri('/delivery-partners/stripe/status/$delivererId'),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('Stripe status failed: ${resp.statusCode} ${resp.body}');
    }
    return DeliveryPartnerStripeStatus.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<DeliveryPartnerCompliance?> fetchComplianceStatus() async {
    final delivererId = await _delivererId();
    final resp = await _client.get(
      _uri('/delivery-partners/compliance/$delivererId'),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception(
        'Compliance status failed: ${resp.statusCode} ${resp.body}',
      );
    }
    return DeliveryPartnerCompliance.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<void> ensureStripeAccount({
    String? country,
    String? email,
    String? phone,
  }) async {
    final delivererId = await _delivererId();
    final resp = await _client.post(
      _uri('/delivery-partners/stripe/account'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'delivererId': delivererId,
        if (country != null) 'country': country,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Stripe account failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<DeliveryPartnerCompliance> startCompliance({
    required String vehicleType,
    String? country,
  }) async {
    final delivererId = await _delivererId();
    final resp = await _client.post(
      _uri('/delivery-partners/compliance/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'delivererId': delivererId,
        'vehicleType': vehicleType,
        if (country != null) 'country': country,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(
        'Compliance start failed: ${resp.statusCode} ${resp.body}',
      );
    }
    return DeliveryPartnerCompliance.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<DeliveryPartnerCompliance> uploadComplianceDocument({
    required String docType,
    required String filePath,
    String? fileName,
  }) async {
    final delivererId = await _delivererId();
    final request = http.MultipartRequest(
      'POST',
      _uri('/delivery-partners/compliance/$delivererId/documents'),
    );
    request.fields['docType'] = docType;
    final normalizedName = _fileNameFromPath(filePath, fileName);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: normalizedName,
      ),
    );
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(
        'Compliance upload failed: ${resp.statusCode} ${resp.body}',
      );
    }
    return DeliveryPartnerCompliance.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<String> createEmbeddedSessionUrl() async {
    final delivererId = await _delivererId();
    final resp = await _client.post(
      _uri('/delivery-partners/stripe/embedded-session'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'delivererId': delivererId,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Stripe session failed: ${resp.statusCode} ${resp.body}');
    }
    final payload = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = payload['url'];
    if (url is! String || url.isEmpty) {
      throw Exception('Stripe session missing URL');
    }
    return url;
  }

  String _fileNameFromPath(String path, String? override) {
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final trimmed = path.replaceAll('\\', '/');
    final parts = trimmed.split('/');
    return parts.isEmpty ? 'upload' : parts.last;
  }
}
