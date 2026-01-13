// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

import 'telegram_webapp.dart';

class TelegramWebAppLinks {
  TelegramWebAppLinks._();

  static void openLink(String url) {
    if (!TelegramWebApp.isAvailable) {
      try {
        js_util.callMethod(js_util.globalThis, 'open', [url, '_blank']);
      } catch (_) {}
      return;
    }
    try {
      final telegram = js_util.getProperty(js_util.globalThis, 'Telegram');
      final webApp = js_util.getProperty(telegram, 'WebApp');
      if (js_util.hasProperty(webApp, 'openLink')) {
        js_util.callMethod(webApp, 'openLink', [url]);
      }
    } catch (_) {}
  }

  static void openTelegramLink(String url) {
    if (!TelegramWebApp.isAvailable) {
      openLink(url);
      return;
    }
    try {
      final telegram = js_util.getProperty(js_util.globalThis, 'Telegram');
      final webApp = js_util.getProperty(telegram, 'WebApp');
      if (js_util.hasProperty(webApp, 'openTelegramLink')) {
        js_util.callMethod(webApp, 'openTelegramLink', [url]);
      } else {
        openLink(url);
      }
    } catch (_) {}
  }
}
