import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_ui/glass_backdrop.dart';

import '../screens/session_gate.dart';

class ConsumerApp extends StatelessWidget {
  const ConsumerApp({super.key});

  static const _foodRed = Color(0xFFE4002B);
  static const _foodRedDark = Color(0xFFFF4D5A);

  ShadColorScheme _foodRedLightScheme() {
    return const ShadRedColorScheme.light().copyWith(
      primary: _foodRed,
      ring: _foodRed,
      destructive: _foodRed,
      selection: const Color(0x33E4002B),
    );
  }

  ShadColorScheme _foodRedDarkScheme() {
    return const ShadRedColorScheme.dark().copyWith(
      primary: _foodRedDark,
      ring: _foodRedDark,
      destructive: _foodRedDark,
      selection: const Color(0x66FF4D5A),
    );
  }

  @override
  Widget build(BuildContext context) {
    const blurSigma = 8.0; // lighter blur for mobile performance
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return ShadApp.custom(
      themeMode: ThemeMode.system,
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
        final textTheme = baseTheme.textTheme.apply(fontFamily: 'Manrope');
        final themedApp = MaterialApp(
          title: 'Ordering Intelligence',
          theme: baseTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
            textTheme: textTheme,
            primaryTextTheme: textTheme,
            cardColor: Colors.white,
            cardTheme: CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 6,
              shadowColor: Colors.black12,
              shape: cardShape,
            ),
          ),
          darkTheme: baseTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
            textTheme: textTheme,
            primaryTextTheme: textTheme,
            cardColor: Colors.white,
            cardTheme: CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 6,
              shadowColor: Colors.black26,
              shape: cardShape,
            ),
          ),
          home: const SessionGate(),
          builder: (context, child) => ShadAppBuilder(child: child!),
        );
        return GlassBackdrop(blurSigma: blurSigma, child: themedApp);
      },
    );
  }
}
