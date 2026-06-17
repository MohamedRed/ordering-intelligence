import 'package:consumer_core/consumer_core.dart';

import '../adapters/mobile_notifications_adapter.dart';
import 'mobile_session_auth.dart';
import 'session_storage.dart';

class SessionRestoreResult {
  final SessionInfo? session;
  final String? error;

  const SessionRestoreResult({this.session, this.error});
}

class SessionRestorer {
  SessionRestorer({
    required this.api,
    required this.storage,
    required this.notifications,
    MobileSessionAuth? authSigner,
  }) : _authSigner = authSigner ?? MobileSessionAuth.fromEnvironment();

  final ChannelGatewayApi api;
  final SessionStorage storage;
  final MobileNotificationsAdapter notifications;
  final MobileSessionAuth? _authSigner;

  Future<SessionRestoreResult> restore() async {
    final stored = await storage.load();
    if (stored == null) {
      return const SessionRestoreResult();
    }
    try {
      final signature = _authSigner?.signSession(sessionId: stored.sessionId);
      final refreshed = await api.fetchMobileSession(
        sessionId: stored.sessionId,
        signature: signature?.signature,
        timestamp: signature?.timestamp,
      );
      await storage.save(refreshed);
      try {
        await notifications.registerDevice(
          customerId: refreshed.customerId,
          sessionId: refreshed.sessionId,
        );
      } catch (_) {}
      return SessionRestoreResult(session: refreshed);
    } catch (err) {
      await storage.clear();
      return SessionRestoreResult(error: err.toString());
    }
  }
}
