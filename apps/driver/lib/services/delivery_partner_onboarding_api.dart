import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/delivery_partner_stripe_status.dart';

const onboardingBaseUrl = String.fromEnvironment(
  'ONBOARDING_SERVICE_URL',
  defaultValue: 'https://onboarding-service-878404493774.europe-west1.run.app',
);

const stripeReturnUrl = String.fromEnvironment(
  'DRIVER_STRIPE_RETURN_URL',
  defaultValue: 'https://driver.onboarding/stripe/return',
);

const stripeRefreshUrl = String.fromEnvironment(
  'DRIVER_STRIPE_REFRESH_URL',
  defaultValue: 'https://driver.onboarding/stripe/refresh',
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

  Future<String> createAccountLink({
    String? returnUrl,
    String? refreshUrl,
  }) async {
    final delivererId = await _delivererId();
    final resp = await _client.post(
      _uri('/delivery-partners/stripe/account-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'delivererId': delivererId,
        'return_url': returnUrl ?? stripeReturnUrl,
        'refresh_url': refreshUrl ?? stripeRefreshUrl,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Stripe link failed: ${resp.statusCode} ${resp.body}');
    }
    final payload = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = payload['url'];
    if (url is! String || url.isEmpty) {
      throw Exception('Stripe link missing URL');
    }
    return url;
  }
}
