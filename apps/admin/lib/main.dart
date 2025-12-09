import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap/https_pins.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/auth/admin_sign_in_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/menu_ingestion/menu_ingestion_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/tenants/tenant_list_screen.dart';
import 'firebase_options.dart';
import 'providers/admin_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enforcePinnedCertificates();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _router(ref);
    return MaterialApp.router(
      title: 'Ordering Intelligence Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      routerConfig: router,
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
          builder: (_, __) => const AdminSignInScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/alerts',
          builder: (_, __) => const AlertsScreen(),
        ),
        GoRoute(
          path: '/menu-ingestion',
          builder: (_, __) => const MenuIngestionScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/tenants',
          builder: (_, __) => const TenantListScreen(),
        ),
      ],
    );
  }
}
