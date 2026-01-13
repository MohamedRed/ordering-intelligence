import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dispatch_api_base.dart';
import 'location_poster.dart';

class DispatchRoute {
  const DispatchRoute({
    required this.id,
    required this.status,
    required this.driverId,
    required this.deliveryIds,
  });

  final String id;
  final String status;
  final String driverId;
  final List<String> deliveryIds;

  factory DispatchRoute.fromJson(String id, Map<String, dynamic> data) {
    final deliveriesRaw = data['deliveryIds'];
    final deliveries = deliveriesRaw is List
        ? deliveriesRaw.map((e) => e.toString()).toList()
        : <String>[];
    return DispatchRoute(
      id: id,
      status: (data['status'] as String?)?.trim() ?? '',
      driverId: (data['driverId'] as String?)?.trim() ?? '',
      deliveryIds: deliveries,
    );
  }
}

class DispatchDriverApi implements LocationPoster {
  DispatchDriverApi({required this.storeId, http.Client? client})
    : _client = client ?? http.Client();

  final String storeId;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse(dispatchBaseUrl + path);

  Future<String> _token() async => fetchDispatchToken();

  Map<String, String> _headers(String token) => dispatchHeaders(token);

  Future<void> claimDriver({required String phoneE164}) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/drivers/me/claim'),
      headers: _headers(token),
      body: jsonEncode({'phoneE164': phoneE164.trim()}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to claim driver: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> updateShift(String status) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/drivers/me/shift/$status'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to update shift: ${resp.statusCode} ${resp.body}',
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
      _uri('/v1/stores/$storeId/drivers/me/location'),
      headers: _headers(token),
      body: jsonEncode({'lat': lat, 'lng': lng, 'accuracyM': accuracyM}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to post location: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  Future<void> acceptAssignment(String assignmentId) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/drivers/me/assignments/$assignmentId/accept'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to accept: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> declineAssignment(String assignmentId) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/drivers/me/assignments/$assignmentId/decline'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to decline: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<DispatchRoute?> getCurrentRoute() async {
    final token = await _token();
    final resp = await _client.get(
      _uri('/v1/stores/$storeId/drivers/me/routes/current'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load route: ${resp.statusCode} ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map &&
        decoded['route'] is Map &&
        decoded['routeId'] is String) {
      return DispatchRoute.fromJson(
        (decoded['routeId'] as String).trim(),
        (decoded['route'] as Map).cast<String, dynamic>(),
      );
    }
    return null;
  }

  Future<void> updateStopStatus({
    required String routeId,
    required String deliveryId,
    required String status,
  }) async {
    final token = await _token();
    final resp = await _client.post(
      _uri('/v1/stores/$storeId/routes/$routeId/stops/$deliveryId/status'),
      headers: _headers(token),
      body: jsonEncode({'status': status}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to update status: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
