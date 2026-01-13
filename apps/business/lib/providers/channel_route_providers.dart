import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/channel_route.dart';

const _adminBaseUrl = String.fromEnvironment(
  'ADMIN_BASE_URL',
  defaultValue: 'https://admin-service-230152279015.us-central1.run.app',
);

class ChannelRouteApi {
  final http.Client _client;
  ChannelRouteApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<ChannelRoute>> listRoutes() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_adminBaseUrl/channel-routes'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load channel routes (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    final list = decoded is List ? decoded : <dynamic>[];
    return list
        .map((e) => ChannelRoute.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ChannelRoute> upsert(ChannelRoute route) async {
    final token = await _token();
    final resp = await _client.post(
      Uri.parse('$_adminBaseUrl/channel-routes'),
      headers: _headers(token),
      body: jsonEncode(route.toJson()),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to save channel route (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return ChannelRoute.fromJson(decoded);
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

final channelRouteApiProvider = Provider<ChannelRouteApi>((ref) => ChannelRouteApi());

final channelRoutesProvider = FutureProvider<List<ChannelRoute>>((ref) async {
  final api = ref.watch(channelRouteApiProvider);
  return api.listRoutes();
});
