import 'telegram_safe_area_insets.dart';
import 'telegram_webapp_bridge_web.dart';

class TelegramWebApp {
  TelegramWebApp._();

  static bool get isAvailable => TelegramWebAppBridge.isAvailable();

  static String get initData => TelegramWebAppBridge.initData();

  static Map<String, dynamic> get initDataUnsafe => TelegramWebAppBridge.initDataUnsafe();

  static String get colorScheme => TelegramWebAppBridge.colorScheme();

  static void ready() => TelegramWebAppBridge.ready();

  static void expand() => TelegramWebAppBridge.expand();

  static void disableVerticalSwipes() => TelegramWebAppBridge.disableVerticalSwipes();

  static TelegramSafeAreaInsets get safeAreaInsets =>
      TelegramWebAppBridge.safeAreaInsets();

  static void hapticImpact([String style = 'light']) =>
      TelegramWebAppBridge.hapticImpact(style);

  static void hapticSelection() => TelegramWebAppBridge.hapticSelection();
}
