import 'telegram_safe_area_insets.dart';

class TelegramWebApp {
  TelegramWebApp._();

  static bool get isAvailable => false;

  static String get initData => '';

  static Map<String, dynamic> get initDataUnsafe => const {};

  static String get colorScheme => 'light';

  static TelegramSafeAreaInsets get safeAreaInsets => const TelegramSafeAreaInsets();

  static void hapticImpact([String style = 'light']) {}

  static void hapticSelection() {}

  static void ready() {}

  static void expand() {}

  static void disableVerticalSwipes() {}
}
