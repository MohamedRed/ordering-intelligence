// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

import 'telegram_safe_area_insets.dart';

TelegramSafeAreaInsets readTelegramSafeAreaInsets(Object? webApp) {
  if (webApp == null) {
    return const TelegramSafeAreaInsets();
  }
  try {
    final safeInset = _readInsets(js_util.getProperty(webApp, 'safeAreaInset'));
    final contentInset =
        _readInsets(js_util.getProperty(webApp, 'contentSafeAreaInset'));
    return safeInset.merge(contentInset);
  } catch (_) {
    return const TelegramSafeAreaInsets();
  }
}

TelegramSafeAreaInsets _readInsets(Object? value) {
  if (value == null) return const TelegramSafeAreaInsets();
  final dartValue = js_util.dartify(value) as Map?;
  if (dartValue == null) return const TelegramSafeAreaInsets();
  return TelegramSafeAreaInsets(
    top: _toDouble(dartValue['top']),
    bottom: _toDouble(dartValue['bottom']),
    left: _toDouble(dartValue['left']),
    right: _toDouble(dartValue['right']),
  );
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
