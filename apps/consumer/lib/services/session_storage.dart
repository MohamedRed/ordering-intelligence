import 'dart:convert';

import 'package:consumer_core/consumer_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_bridge.dart';

class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'consumer.session.v1';
  final FlutterSecureStorage _storage;

  Future<void> save(SessionInfo session) async {
    final payload = jsonEncode(session.toJson());
    await _storage.write(key: _sessionKey, value: payload);
    await SessionBridge.save(session);
  }

  Future<SessionInfo?> load() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SessionInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    await SessionBridge.clear();
  }
}
