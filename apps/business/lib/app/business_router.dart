import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/channels/channel_routes_screen.dart';
import '../features/dispatch/dispatch_screen.dart';
import '../features/group_orders/group_order_detail_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/order_list_screen.dart';
import '../features/settings/store_settings_screen.dart';
import '../features/voice/voice_screen.dart';
import '../features/wait_time/wait_time_screen.dart';
import '../providers/app_providers.dart';

GoRouter buildBusinessRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/orders',
    refreshListenable: ref.watch(authNotifierProvider),
    redirect: (context, state) {
      final auth = ref.read(authNotifierProvider);
      final loggingIn = state.matchedLocation == '/sign-in';

      if (!auth.isAuthenticated) {
        return loggingIn ? null : '/sign-in';
      }
      if (loggingIn) {
        return '/orders';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        pageBuilder: (_, __) => const NoTransitionPage(child: SignInScreen()),
      ),
      GoRoute(
        path: '/orders',
        pageBuilder: (_, __) => const NoTransitionPage(child: OrderListScreen()),
      ),
      GoRoute(
        path: '/deliveries',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: OrderListScreen(
            title: 'Deliveries',
            fulfillmentFilter: 'delivery',
          ),
        ),
      ),
      GoRoute(
        path: '/orders/:orderId',
        builder: (_, state) =>
            OrderDetailScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/group-orders/:groupOrderId',
        builder: (_, state) => GroupOrderDetailScreen(
            groupOrderId: state.pathParameters['groupOrderId']!),
      ),
      GoRoute(
        path: '/menu',
        pageBuilder: (_, __) => const NoTransitionPage(child: MenuScreen()),
      ),
      GoRoute(
        path: '/voice',
        pageBuilder: (_, __) => const NoTransitionPage(child: VoiceScreen()),
      ),
      GoRoute(
        path: '/channels',
        pageBuilder: (_, __) =>
            const NoTransitionPage(child: ChannelRoutesScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, __) => const NoTransitionPage(child: StoreSettingsScreen()),
      ),
      GoRoute(
        path: '/dispatch',
        pageBuilder: (_, __) => const NoTransitionPage(child: DispatchScreen()),
      ),
      GoRoute(
        path: '/wait-time',
        pageBuilder: (_, __) => const NoTransitionPage(child: WaitTimeScreen()),
      ),
    ],
  );
}
