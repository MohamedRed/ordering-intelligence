import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/ui/glass_backdrop.dart';
import 'screens/tv/tv_session_gate.dart';

/// TV / living‑room entrypoint for the consumer app.
/// Uses the same feature set as mobile but optimizes focus navigation,
/// typography, and card readability for 10‑foot experiences.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConsumerTvApp());
}

class ConsumerTvApp extends StatelessWidget {
  const ConsumerTvApp({super.key});

  static const _accent = Color(0xFFE4002B);
  static const _accentDark = Color(0xFFFF4D5A);

  ShadColorScheme _lightScheme() => const ShadRedColorScheme.light().copyWith(
        primary: _accent,
        ring: _accent,
        destructive: _accent,
        selection: const Color(0x33E4002B),
      );

  ShadColorScheme _darkScheme() => const ShadRedColorScheme.dark().copyWith(
        primary: _accentDark,
        ring: _accentDark,
        destructive: _accentDark,
        selection: const Color(0x66FF4D5A),
      );

  @override
  Widget build(BuildContext context) {
    const blurSigma = 8.0; // lighter blur for TV performance
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
    );

    return ShadApp.custom(
      themeMode: ThemeMode.light,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: _lightScheme(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: _darkScheme(),
      ),
      appBuilder: (context) {
        final base = Theme.of(context);
        final textTheme = base.textTheme.copyWith(
          displayLarge: base.textTheme.displayLarge?.copyWith(fontSize: 52),
          displayMedium: base.textTheme.displayMedium?.copyWith(fontSize: 44),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontSize: 32),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 26),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 20),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 18),
        );

        final themedApp = MaterialApp(
          title: 'Ordering Intelligence TV',
          useInheritedMediaQuery: true,
          debugShowCheckedModeBanner: false,
          scrollBehavior: _TvScrollBehavior(),
          shortcuts: const <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.select): ActivateIntent(),
          },
          theme: base.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
            textTheme: textTheme,
            cardColor: Colors.white,
            cardTheme: CardTheme(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 6,
              shadowColor: Colors.black26,
              shape: cardShape,
            ),
          ),
          home: const _TvFocusShell(child: TvSessionGate()),
          builder: (context, child) => ShadAppBuilder(child: child!),
        );

        return GlassBackdrop(blurSigma: blurSigma, child: themedApp);
      },
    );
  }
}

/// Enables d‑pad navigation and scroll with remotes/gamepads.
class _TvScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}

/// Wraps content with focus traversal so remote arrows move focus predictably.
class _TvFocusShell extends StatelessWidget {
  const _TvFocusShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: child,
    );
  }
}
