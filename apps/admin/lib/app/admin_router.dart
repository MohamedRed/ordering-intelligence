import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/alerts/alerts_screen.dart';
import '../features/auth/admin_sign_in_screen.dart';
import '../features/channels/channel_routes_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/demo/demo_screen.dart';
import '../features/menu_ingestion/menu_ingestion_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/tenants/tenant_list_screen.dart';
import '../models/tenant.dart';
import '../providers/admin_providers.dart';

GoRouter buildAdminRouter(WidgetRef ref) {
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
