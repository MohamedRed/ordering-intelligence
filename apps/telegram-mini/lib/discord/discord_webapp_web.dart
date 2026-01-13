// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

import 'discord_webapp_stub.dart';

class DiscordWebApp {
  DiscordWebApp._();

  static Object? _bridge() {
    try {
      return js_util.getProperty(js_util.globalThis, 'DiscordWebApp');
    } catch (_) {
      return null;
    }
  }

  static bool get isAvailable {
    final bridge = _bridge();
    if (bridge == null) return false;
    try {
      if (js_util.hasProperty(bridge, 'isAvailable')) {
        final value = js_util.callMethod(bridge, 'isAvailable', const []);
        return value == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<DiscordAuthResult> authorize({
    required String clientId,
    List<String> scopes = const ['identify'],
    String? redirectUri,
  }) async {
    final bridge = _bridge();
    if (bridge == null) {
      throw UnsupportedError('Discord WebApp bridge missing');
    }
    final promise = js_util.callMethod(bridge, 'authorize', [
      clientId,
      scopes,
      redirectUri,
    ]);
    final result = await js_util.promiseToFuture(promise);
    final map = Map<String, dynamic>.from(js_util.dartify(result) as Map);
    return DiscordAuthResult(
      code: (map['code'] ?? '').toString(),
      redirectUri: (map['redirectUri'] ?? map['redirect_uri'] ?? '').toString(),
      accessToken: (map['accessToken'] ?? map['access_token'] ?? '').toString(),
    );
  }
}
