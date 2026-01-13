import 'package:consumer_core/consumer_core.dart';

import '../adapters/mobile_notifications_adapter.dart';
import 'mobile_session_auth.dart';
import 'session_storage.dart';

class SessionTerminator {
  SessionTerminator({
    required this.api,
    required this.notifications,
    required this.storage,
    MobileSessionAuth? authSigner,
  }) : _authSigner = authSigner ?? MobileSessionAuth.fromEnvironment();

  final ChannelGatewayApi api;
  final MobileNotificationsAdapter notifications;
  final SessionStorage storage;
  final MobileSessionAuth? _authSigner;

  Future<void> terminate(SessionInfo session) async {
    try {
      await notifications.unregisterDevice(sessionId: session.sessionId);
    } catch (_) {}

    try {
      final signature = _authSigner?.signSession(sessionId: session.sessionId);
      await api.endMobileSession(
        sessionId: session.sessionId,
        signature: signature?.signature,
        timestamp: signature?.timestamp,
      );
    } catch (_) {}

    await storage.clear();
  }
}
