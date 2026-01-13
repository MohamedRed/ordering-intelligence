import 'package:consumer_core/consumer_core.dart';

import 'tv_pairing_service.dart';
import 'tv_session_storage.dart';

class TvSessionRestoreResult {
  const TvSessionRestoreResult({this.session, this.token, this.error});

  final SessionInfo? session;
  final String? token;
  final String? error;
}

class TvSessionRestorer {
  TvSessionRestorer({
    required this.service,
    required this.storage,
  });

  final TvPairingService service;
  final TvSessionStorage storage;

  Future<TvSessionRestoreResult> restore() async {
    final token = await storage.loadToken();
    if (token == null || token.isEmpty) {
      return const TvSessionRestoreResult();
    }
    try {
      final session = await service.fetchSession(sessionToken: token);
      return TvSessionRestoreResult(session: session, token: token);
    } catch (err) {
      await storage.clear();
      return TvSessionRestoreResult(error: err.toString());
    }
  }
}
