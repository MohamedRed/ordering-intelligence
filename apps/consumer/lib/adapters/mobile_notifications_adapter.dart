import 'dart:io';

import 'package:consumer_core/consumer_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../services/mobile_session_auth.dart';

class MobileNotificationsAdapter implements NotificationsAdapter {
  MobileNotificationsAdapter({required this.api, MobileSessionAuth? authSigner})
    : _authSigner = authSigner ?? MobileSessionAuth.fromEnvironment();

  final ChannelGatewayApi api;
  final MobileSessionAuth? _authSigner;

  @override
  Future<void> registerDevice({
    required String customerId,
    required String sessionId,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    final platform = kIsWeb
        ? 'web'
        : Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : 'mobile';
    final signature = _authSigner?.signSession(sessionId: sessionId);
    await api.registerMobileDeviceToken(
      sessionId: sessionId,
      deviceToken: token,
      platform: platform,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
    messaging.onTokenRefresh.listen((nextToken) async {
      if (nextToken.isEmpty) return;
      final refreshedSignature = _authSigner?.signSession(sessionId: sessionId);
      await api.registerMobileDeviceToken(
        sessionId: sessionId,
        deviceToken: nextToken,
        platform: platform,
        signature: refreshedSignature?.signature,
        timestamp: refreshedSignature?.timestamp,
      );
    });
  }

  @override
  Future<void> unregisterDevice({required String sessionId}) async {
    if (Firebase.apps.isEmpty) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        final signature = _authSigner?.signSession(sessionId: sessionId);
        await api.unregisterMobileDeviceToken(
          sessionId: sessionId,
          deviceToken: token,
          signature: signature?.signature,
          timestamp: signature?.timestamp,
        );
      } catch (_) {}
    }
    await FirebaseMessaging.instance.deleteToken();
  }
}
