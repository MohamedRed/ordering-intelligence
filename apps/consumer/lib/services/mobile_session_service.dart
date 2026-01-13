import 'package:consumer_core/consumer_core.dart';

import 'mobile_client_info.dart';
import 'mobile_session_auth.dart';

class MobileSessionService {
  MobileSessionService({
    required this.api,
    MobileSessionAuth? authSigner,
    MobileClientInfo? clientInfo,
  })  : _authSigner = authSigner ?? MobileSessionAuth.fromEnvironment(),
        _clientInfo = clientInfo ?? MobileClientInfo.fromEnvironment();

  final ChannelGatewayApi api;
  final MobileSessionAuth? _authSigner;
  final MobileClientInfo _clientInfo;

  Future<SessionInfo> startSession({
    required AuthSession auth,
    String? storeId,
    String? locale,
    String? clientVersion,
  }) async {
    final overrideVersion = clientVersion?.trim();
    final resolvedVersion = await _clientInfo.resolveVersion();
    final signature = _authSigner?.sign(
      provider: auth.provider.id,
      subject: auth.subject,
    );
    return api.startMobileSession(
      auth: auth,
      storeId: storeId,
      locale: locale,
      clientVersion:
          (overrideVersion != null && overrideVersion.isNotEmpty)
              ? overrideVersion
              : resolvedVersion,
      clientPlatform: _clientInfo.platform,
      clientApp: _clientInfo.app,
      clientOs: _clientInfo.os,
      clientOsVersion: _clientInfo.osVersion,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }
}
