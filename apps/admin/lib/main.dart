import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bootstrap/https_pins.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/auth/admin_sign_in_screen.dart';
import 'features/channels/channel_routes_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/demo/demo_screen.dart';
import 'features/menu_ingestion/menu_ingestion_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/tenants/tenant_list_screen.dart';
import 'firebase_options.dart';
import 'models/tenant.dart';
import 'providers/admin_providers.dart';
import '../../shared/ui/glass_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enforcePinnedCertificates();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _router(ref);
    final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
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
        final textTheme =
            GoogleFonts.manropeTextTheme(base.textTheme);
        return MaterialApp.router(
          title: 'Ordering Intelligence Admin',
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
          routerConfig: router,
          builder: (context, child) => GlassBackdrop(
            child: ShadAppBuilder(child: child!),
          ),
        );
      },
    );
  }

  GoRouter _router(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: ref.watch(adminAuthProvider),
      redirect: (context, state) {
        final auth = ref.read(adminAuthProvider);
        final loggingIn = state.matchedLocation == '/login';
        if (!auth.isAuthenticated) {
          return loggingIn ? null : '/login';
        }
        if (loggingIn) {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (_, __) => const NoTransitionPage(child: AdminSignInScreen()),
        ),
        GoRoute(
          path: '/dashboard',
          pageBuilder: (_, __) => const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/alerts',
          pageBuilder: (_, __) => const NoTransitionPage(child: AlertsScreen()),
        ),
        GoRoute(
          path: '/menu-ingestion',
          pageBuilder: (_, __) => const NoTransitionPage(child: MenuIngestionScreen()),
        ),
        GoRoute(
          path: '/demo',
          pageBuilder: (_, __) => const NoTransitionPage(child: DemoScreen()),
        ),
        GoRoute(
          path: '/channels',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: ChannelRoutesScreen()),
        ),
        GoRoute(
          path: '/tenants',
          pageBuilder: (_, __) => const NoTransitionPage(child: TenantListScreen()),
        ),
        GoRoute(
          path: '/tenants/:tenantId/onboarding',
          pageBuilder: (_, state) {
            final tenantId = state.pathParameters['tenantId'] ?? '';
            final tenant = state.extra is Tenant ? state.extra as Tenant : null;
            return NoTransitionPage(child: OnboardingScreen(tenantId: tenantId, tenant: tenant));
          },
        ),
      ],
    );
  }
}
