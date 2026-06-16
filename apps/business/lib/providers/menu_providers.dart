import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/menu.dart';

const _baseUrl = String.fromEnvironment(
  'ORDER_SERVICE_URL',
  defaultValue: 'https://order-service-230152279015.us-central1.run.app',
);
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

class MenuApi {
  final http.Client _client;
  MenuApi({http.Client? client}) : _client = client ?? http.Client();

  Future<MenuRecordModel> fetchMenu() async {
    final token = await _token();
    final resp = await _client.get(Uri.parse('$_baseUrl/stores/$_storeId/menu'),
        headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch menu');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return MenuRecordModel.fromJson(data);
  }

  Future<void> saveMenu(MenuRecordModel menu) async {
    final token = await _token();
    final resp = await _client.put(
      Uri.parse('$_baseUrl/stores/$_storeId/menu'),
      headers: _headers(token),
      body: jsonEncode(menu.toJson()),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to save menu');
    }
  }

  Map<String, String> _headers(String? token) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }
}

final menuApiProvider = Provider<MenuApi>((ref) => MenuApi());
final menuRecordProvider = FutureProvider<MenuRecordModel>((ref) async {
  final api = ref.watch(menuApiProvider);
  return api.fetchMenu();
});
