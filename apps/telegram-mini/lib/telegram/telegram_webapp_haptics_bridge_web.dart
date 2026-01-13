// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

import 'dart:js_util' as js_util;

void triggerTelegramHapticImpact(Object? webApp, String style) {
  if (webApp == null) return;
  try {
    final haptics = js_util.getProperty(webApp, 'HapticFeedback');
    if (haptics == null) return;
    js_util.callMethod(haptics, 'impactOccurred', [style]);
  } catch (_) {}
}

void triggerTelegramHapticSelection(Object? webApp) {
  if (webApp == null) return;
  try {
    final haptics = js_util.getProperty(webApp, 'HapticFeedback');
    if (haptics == null) return;
    js_util.callMethod(haptics, 'selectionChanged', const []);
  } catch (_) {}
}
