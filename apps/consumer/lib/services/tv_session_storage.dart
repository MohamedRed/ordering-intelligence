import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TvSessionStorage {
  TvSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'consumer.tv.session.token.v1';
  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> loadToken() async {
    final raw = await _storage.read(key: _tokenKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
  }
}
