import 'package:consumer_core/consumer_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../services/session_bridge.dart';

class AutoDiagnosticsSnapshot {
  AutoDiagnosticsSnapshot({
    required this.session,
    required this.sharedSession,
    required this.firebaseReady,
    required this.fcmToken,
  });

  final SessionInfo session;
  final Map<String, dynamic>? sharedSession;
  final bool firebaseReady;
  final String? fcmToken;

  String? get sharedSessionId => sharedSession?['sessionId']?.toString();
  String? get sharedCustomerId => sharedSession?['customerId']?.toString();

  bool get sharedSessionMatches =>
      sharedSessionId != null && sharedSessionId == session.sessionId;
}

class AutoDiagnosticsService {
  Future<AutoDiagnosticsSnapshot> load(SessionInfo session) async {
    final shared = await SessionBridge.load();
    final firebaseReady = Firebase.apps.isNotEmpty;
    String? token;
    if (firebaseReady) {
      token = await FirebaseMessaging.instance.getToken();
    }
    return AutoDiagnosticsSnapshot(
      session: session,
      sharedSession: shared,
      firebaseReady: firebaseReady,
      fcmToken: token,
    );
  }
}
