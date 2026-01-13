import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/marketplace_offer.dart';
import 'dispatch_api_base.dart';
import 'location_poster.dart';

class MarketplaceDispatchApi implements LocationPoster {
  MarketplaceDispatchApi({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse(dispatchBaseUrl + path).replace(queryParameters: query);
  }

  Future<String> _token() async => fetchDispatchToken();

  Map<String, String> _headers(String token) => dispatchHeaders(token);

  Future<void> registerDeliverer({
    String displayName = '',
    required String phoneE164,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/marketplace/deliverers/me/register'),
      headers: _headers(token),
      body: jsonEncode({
        'displayName': displayName.trim(),
        'phoneE164': phoneE164.trim(),
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Registration failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> setAvailability(bool available) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/marketplace/deliverers/me/availability'),
      headers: _headers(token),
      body: jsonEncode({'available': available}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Availability update failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  @override
  Future<void> postLocation({
    required double lat,
    required double lng,
    double accuracyM = 0,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/marketplace/deliverers/me/location'),
      headers: _headers(token),
      body: jsonEncode({'lat': lat, 'lng': lng, 'accuracyM': accuracyM}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Location update failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<List<MarketplaceOffer>> listOffers({String? status}) async {
    final token = await _token();
    final resp = await _client.get(
      _uri(
        '/v1/marketplace/offers',
        status == null ? null : {'status': status},
      ),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Offer list failed: ${resp.statusCode} ${resp.body}');
    }
    final payload = jsonDecode(resp.body);
    final offersRaw = payload is Map ? payload['offers'] : null;
    if (offersRaw is List) {
      return offersRaw
          .whereType<Map>()
          .map((e) => MarketplaceOffer.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return [];
  }

  Future<void> acceptOffer(String offerId) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/marketplace/offers/$offerId/accept'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Accept failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    String? offerId,
    String? storeId,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/marketplace/orders/$orderId/status'),
      headers: _headers(token),
      body: jsonEncode({
        'status': status,
        if (offerId != null) 'offerId': offerId,
        if (storeId != null) 'storeId': storeId,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Status update failed: ${resp.statusCode} ${resp.body}');
    }
  }
}
