// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

import 'telegram_safe_area_insets.dart';
import 'telegram_webapp_haptics_bridge_web.dart';
import 'telegram_webapp_safe_area_bridge_web.dart';

class TelegramWebAppBridge {
  TelegramWebAppBridge._();

  static Object? _webApp() {
    try {
      final telegram = js_util.getProperty(js_util.globalThis, 'Telegram');
      if (telegram == null) return null;
      return js_util.getProperty(telegram, 'WebApp');
    } catch (_) {
      return null;
    }
  }

  static bool isAvailable() => _webApp() != null;

  static String initData() {
    final webApp = _webApp();
    if (webApp == null) return '';
    try {
      final value = js_util.getProperty(webApp, 'initData');
      return value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic> initDataUnsafe() {
    final webApp = _webApp();
    if (webApp == null) return const {};
    try {
      final value = js_util.getProperty(webApp, 'initDataUnsafe');
      final dartValue = js_util.dartify(value);
      return Map<String, dynamic>.from(dartValue as Map);
    } catch (_) {
      return const {};
    }
  }

  static String colorScheme() {
    final webApp = _webApp();
    if (webApp == null) return 'light';
    try {
      final value = js_util.getProperty(webApp, 'colorScheme');
      return value?.toString() ?? 'light';
    } catch (_) {
      return 'light';
    }
  }

  static void ready() {
    final webApp = _webApp();
    if (webApp == null) return;
    try {
      js_util.callMethod(webApp, 'ready', const []);
    } catch (_) {}
  }

  static void expand() {
    final webApp = _webApp();
    if (webApp == null) return;
    try {
      js_util.callMethod(webApp, 'expand', const []);
    } catch (_) {}
  }

  static void disableVerticalSwipes() {
    final webApp = _webApp();
    if (webApp == null) return;
    try {
      if (js_util.hasProperty(webApp, 'disableVerticalSwipes')) {
        js_util.callMethod(webApp, 'disableVerticalSwipes', const []);
      }
    } catch (_) {}
  }

  static TelegramSafeAreaInsets safeAreaInsets() {
    return readTelegramSafeAreaInsets(_webApp());
  }

  static void hapticImpact(String style) {
    triggerTelegramHapticImpact(_webApp(), style);
  }

  static void hapticSelection() {
    triggerTelegramHapticSelection(_webApp());
  }
}
