import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bootstrap/https_pins.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/orders/order_list_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'features/group_orders/group_order_detail_screen.dart';
import 'features/dispatch/dispatch_screen.dart';
import 'features/channels/channel_routes_screen.dart';
import 'features/settings/store_settings_screen.dart';
import 'features/wait_time/wait_time_screen.dart';
import 'features/voice/voice_screen.dart';
import 'firebase_messaging_setup.dart';
import 'fcm_token_manager.dart';
import 'notification_service.dart';
import 'providers/offline_queue.dart';
import 'providers/app_providers.dart';
import 'providers/highlight_provider.dart';
import '../../shared/ui/glass_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enforcePinnedCertificates();
  await initFirebaseAndMessaging();
  await NotificationService.instance.init();
  FirebaseMessaging.onBackgroundMessage(backgroundHandler);
  // Subscribe to store topic for push (env configured).
  final base = Uri.base;
  String? storeId =
      (base.queryParameters['storeId'] ?? base.queryParameters['store_id'])
          ?.trim();
  if (storeId == null || storeId.isEmpty) {
    final frag = base.fragment; // e.g. "/orders?storeId=..."
    final qIndex = frag.indexOf('?');
    if (qIndex >= 0 && qIndex + 1 < frag.length) {
      try {
        final qp = Uri.splitQueryString(frag.substring(qIndex + 1));
        storeId = (qp['storeId'] ?? qp['store_id'])?.trim();
      } catch (_) {
        // ignore
      }
    }
  }
  final effectiveStoreId = (storeId != null && storeId.isNotEmpty)
      ? storeId
      : const String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');
  await subscribeToStoreTopic(effectiveStoreId);
  // Attempt a background flush of any queued status updates at startup.
  await StatusUpdateQueue().flushIfAny((_) async {});
  final initialPayload = NotificationService.instance.takePayload();
  runApp(ProviderScope(
    overrides: [
      if (initialPayload != null)
        highlightedOrderIdProvider.overrideWith((ref) => initialPayload),
      if (initialPayload != null)
        pendingOrderNavigationProvider.overrideWith((ref) => initialPayload),
    ],
    child: const BusinessApp(),
  ));
}

class BusinessApp extends ConsumerWidget {
  const BusinessApp({super.key});

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
    final router = _createRouter(ref);
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
        final textTheme = GoogleFonts.manropeTextTheme(base.textTheme);
        return MaterialApp.router(
          title: 'Ordering Intelligence',
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
}
