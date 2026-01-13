import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'firebase_options.dart';
import 'screens/driver_home_screen.dart';
import 'screens/marketplace_home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/store_prefs.dart';
import '../../shared/ui/glass_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  await StorePrefs.instance.load();
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

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
    const enableGlass = true; // flip to false on low-end devices if needed
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return ShadApp.custom(
      themeMode: ThemeMode.light,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: _foodRedLightScheme(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: _foodRedDarkScheme(),
      ),
      appBuilder: (context) {
        final base = Theme.of(context);
        final textTheme = GoogleFonts.manropeTextTheme(base.textTheme);
        final themedApp = MaterialApp(
          title: 'Driver',
          theme: base.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            textTheme: textTheme,
            cardColor: Colors.white,
            canvasColor: Colors.transparent,
            cardTheme: CardTheme(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 6,
              shadowColor: Colors.black12,
              shape: cardShape,
            ),
          ),
          darkTheme: base.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            textTheme: textTheme,
            cardColor: Colors.white,
            canvasColor: Colors.transparent,
            cardTheme: CardTheme(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 6,
              shadowColor: Colors.black26,
              shape: cardShape,
            ),
          ),
          builder: (context, child) => ShadAppBuilder(child: child!),
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data == null) {
                return const SignInScreen();
              }
              final mode = StorePrefs.instance.mode();
              if (mode == 'marketplace') {
                return const MarketplaceHomeScreen();
              }
              return const DriverHomeScreen();
            },
          ),
        );
        if (!enableGlass) return themedApp;
        return GlassBackdrop(child: themedApp);
      },
    );
  }
}
