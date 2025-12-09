import 'dart:convert';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../features/menu/menu_editor.dart';

const _baseUrl = String.fromEnvironment('ORDER_SERVICE_URL',
    defaultValue: 'http://localhost:8082');
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

class MenuApi {
  final http.Client _client;
  MenuApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<MenuItemModel>> fetchMenu() async {
    final token = await _token();
    final resp = await _client.get(Uri.parse('$_baseUrl/stores/$_storeId/menu'),
        headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch menu');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<void> saveMenu(List<MenuItemModel> items) async {
    final token = await _token();
    final resp = await _client.put(
      Uri.parse('$_baseUrl/stores/$_storeId/menu'),
      headers: _headers(token),
      body: jsonEncode({'items': items.map((e) => e.toJson()).toList()}),
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
    return user != null ? user.getIdToken() : null;
  }
}

final menuApiProvider = Provider<MenuApi>((ref) => MenuApi());
final menuItemsProvider = FutureProvider<List<MenuItemModel>>((ref) async {
  final api = ref.watch(menuApiProvider);
  return api.fetchMenu();
});
