import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_ui/consumer_ui.dart';

import '../platform/web_mini_app_platform_stub.dart'
    if (dart.library.html) '../platform/web_mini_app_platform.dart';
import '../telegram/telegram_webapp.dart';
class TelegramMiniApp extends StatefulWidget {
  const TelegramMiniApp({super.key});

  static const _foodRed = Color(0xFFE4002B);
  static const _foodRedDark = Color(0xFFFF4D5A);

  @override
  State<TelegramMiniApp> createState() => _TelegramMiniAppState();
}

class _TelegramMiniAppState extends State<TelegramMiniApp>
    with WidgetsBindingObserver {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeMode = _resolveThemeMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final next = _resolveThemeMode();
    if (next != _themeMode) {
      setState(() => _themeMode = next);
    }
  }

  ThemeMode _resolveThemeMode() {
    if (TelegramWebApp.isAvailable) {
      final scheme = TelegramWebApp.colorScheme.toLowerCase();
      return scheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }
  ShadColorScheme _foodRedLightScheme() {
    return const ShadRedColorScheme.light().copyWith(
      primary: TelegramMiniApp._foodRed,
      ring: TelegramMiniApp._foodRed,
      destructive: TelegramMiniApp._foodRed,
      selection: const Color(0x33E4002B),
    );
  }

  ShadColorScheme _foodRedDarkScheme() {
    return const ShadRedColorScheme.dark().copyWith(
      primary: TelegramMiniApp._foodRedDark,
      ring: TelegramMiniApp._foodRedDark,
      destructive: TelegramMiniApp._foodRedDark,
      selection: const Color(0x66FF4D5A),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      themeMode: _themeMode,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: _foodRedLightScheme(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: _foodRedDarkScheme(),
      ),
      appBuilder: (context) {
        final baseTheme = Theme.of(context);
        return MaterialApp(
          title: 'Ordering Mini App',
          theme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Manrope'),
            primaryTextTheme:
                baseTheme.primaryTextTheme.apply(fontFamily: 'Manrope'),
          ),
          darkTheme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: 'Manrope'),
            primaryTextTheme:
                baseTheme.primaryTextTheme.apply(fontFamily: 'Manrope'),
          ),
          home: MiniAppScreen(platform: WebMiniAppPlatform()),
          builder: (context, child) => ShadAppBuilder(child: child!),
        );
      },
    );
  }
}
