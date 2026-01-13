import 'dart:io';

import 'package:consumer_core/consumer_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class MobileNotificationsAdapter implements NotificationsAdapter {
  MobileNotificationsAdapter({required this.api});

  final ChannelGatewayApi api;

  @override
  Future<void> registerDevice({required String customerId, required String sessionId}) async {
    if (Firebase.apps.isEmpty) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'mobile';
    await api.registerMobileDeviceToken(
      sessionId: sessionId,
      deviceToken: token,
      platform: platform,
    );
    messaging.onTokenRefresh.listen((nextToken) async {
      if (nextToken.isEmpty) return;
      await api.registerMobileDeviceToken(
        sessionId: sessionId,
        deviceToken: nextToken,
        platform: platform,
      );
    });
  }

  @override
  Future<void> unregisterDevice({required String sessionId}) async {
    if (Firebase.apps.isEmpty) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await api.unregisterMobileDeviceToken(
          sessionId: sessionId,
          deviceToken: token,
        );
      } catch (_) {}
    }
    await FirebaseMessaging.instance.deleteToken();
  }
}
