import 'dart:convert';

import 'package:consumer_core/consumer_core.dart';
import 'package:http/http.dart' as http;

class TvPairingStartResponse {
  const TvPairingStartResponse({
    required this.pairingId,
    required this.code,
    required this.pairUrl,
    required this.expiresAt,
    required this.pollIntervalSeconds,
  });

  final String pairingId;
  final String code;
  final String pairUrl;
  final DateTime? expiresAt;
  final int pollIntervalSeconds;

  factory TvPairingStartResponse.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['expiresAt']?.toString() ?? '';
    return TvPairingStartResponse(
      pairingId: (json['pairingId'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      pairUrl: (json['pairUrl'] ?? '').toString(),
      expiresAt: expiresRaw.isEmpty ? null : DateTime.tryParse(expiresRaw),
      pollIntervalSeconds: int.tryParse('${json['pollIntervalSeconds'] ?? 0}') ?? 0,
    );
  }
}

class TvPairingStateResponse {
  const TvPairingStateResponse({
    required this.status,
    this.pairingId = '',
    this.code = '',
    this.sessionId = '',
    this.sessionToken = '',
  });

  final String status;
  final String pairingId;
  final String code;
  final String sessionId;
  final String sessionToken;

  bool get isLinked => status.toLowerCase() == 'linked' && sessionToken.isNotEmpty;

  factory TvPairingStateResponse.fromJson(Map<String, dynamic> json) {
    return TvPairingStateResponse(
      status: (json['status'] ?? '').toString(),
      pairingId: (json['pairingId'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      sessionId: (json['sessionId'] ?? '').toString(),
      sessionToken: (json['sessionToken'] ?? json['session'] ?? '').toString(),
    );
  }
}

class TvPairingService {
  TvPairingService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final full = '$normalized$path';
    return Uri.parse(full).replace(queryParameters: query);
  }

  Future<TvPairingStartResponse> startPairing({
    String? deviceId,
    String? deviceType,
    String? deviceName,
    String? locale,
    String? clientVersion,
    String? clientPlatform,
  }) async {
    final response = await _client.post(
      _buildUri('/tv/pair/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'deviceType': deviceType,
        'deviceName': deviceName,
        'locale': locale,
        'clientVersion': clientVersion,
        'clientPlatform': clientPlatform,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TV pairing start failed (${response.statusCode})');
    }
    return TvPairingStartResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TvPairingStateResponse> fetchState({
    required String pairingId,
  }) async {
    final response = await _client.get(
      _buildUri('/tv/pair/state', {'pairingId': pairingId}),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TV pairing state failed (${response.statusCode})');
    }
    return TvPairingStateResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TvPairingStateResponse> completePairing({
    String? pairingId,
    String? code,
    required String sessionId,
    String? deviceName,
  }) async {
    final response = await _client.post(
      _buildUri('/tv/pair/complete'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pairingId': pairingId,
        'code': code,
        'sessionId': sessionId,
        'deviceName': deviceName,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TV pairing complete failed (${response.statusCode})');
    }
    return TvPairingStateResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SessionInfo> fetchSession({
    required String sessionToken,
  }) async {
    final response = await _client.get(
      _buildUri('/tv/session'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sessionToken',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TV session fetch failed (${response.statusCode})');
    }
    return SessionInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> endSession({
    required String sessionToken,
  }) async {
    final request = http.Request('DELETE', _buildUri('/tv/session'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $sessionToken';
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TV session end failed (${response.statusCode})');
    }
  }
}
