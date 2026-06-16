import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/business_app.dart';
import '../fcm_token_manager.dart';
import '../firebase_messaging_setup.dart';
import '../notification_service.dart';
import '../providers/highlight_provider.dart';
import '../providers/offline_queue.dart';
import 'ci_semantics.dart';
import 'https_pins.dart';

Future<void> bootstrapBusinessApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableCiSemantics();
  enforcePinnedCertificates();
  await initFirebaseAndMessaging();
  await NotificationService.instance.init();
  FirebaseMessaging.onBackgroundMessage(backgroundHandler);
  final effectiveStoreId = _resolveStoreId();
  await subscribeToStoreTopic(effectiveStoreId);
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

String _resolveStoreId() {
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
        // Avoid blocking boot if malformed URLs show up.
      }
    }
  }
  return (storeId != null && storeId.isNotEmpty)
      ? storeId
      : const String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');
}
