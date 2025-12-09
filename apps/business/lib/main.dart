import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap/https_pins.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/orders/order_list_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'firebase_messaging_setup.dart';
import 'fcm_token_manager.dart';
import 'notification_service.dart';
import 'providers/offline_queue.dart';
import 'providers/app_providers.dart';
import 'providers/highlight_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enforcePinnedCertificates();
  await initFirebaseAndMessaging();
  await NotificationService.instance.init();
  FirebaseMessaging.onBackgroundMessage(backgroundHandler);
  // Subscribe to store topic for push (env configured).
  const storeId =
      String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');
  await subscribeToStoreTopic(storeId);
  // Attempt a background flush of any queued status updates at startup.
  await StatusUpdateQueue().flushIfAny((_) async {});
  final initialPayload = NotificationService.instance.takePayload();
  runApp(ProviderScope(
    overrides: [
      if (initialPayload != null)
        highlightedOrderIdProvider
            .overrideWith((ref) => StateController(initialPayload)),
      if (initialPayload != null)
        pendingOrderNavigationProvider
            .overrideWith((ref) => StateController(initialPayload)),
    ],
    child: const BusinessApp(),
  ));
}

class BusinessApp extends ConsumerWidget {
  const BusinessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _createRouter(ref);
    return MaterialApp.router(
      title: 'Ordering Intelligence',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }

  GoRouter _createRouter(WidgetRef ref) {
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
          builder: (_, __) => const SignInScreen(),
        ),
        GoRoute(
          path: '/orders',
          builder: (_, __) => const OrderListScreen(),
        ),
        GoRoute(
          path: '/orders/:orderId',
          builder: (_, state) =>
              OrderDetailScreen(orderId: state.pathParameters['orderId']!),
        ),
        GoRoute(
          path: '/menu',
          builder: (_, __) => const MenuScreen(),
        ),
      ],
    );
  }
}
