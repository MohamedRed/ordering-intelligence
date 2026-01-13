import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/material.dart';

import '../../platform/tv_mini_app_platform.dart';
import '../../services/api_config.dart';
import '../../services/tv_pairing_service.dart';
import '../../services/tv_session_restorer.dart';
import '../../services/tv_session_storage.dart';
import '../session/session_loading_view.dart';
import 'tv_pairing_screen.dart';

class TvSessionGate extends StatefulWidget {
  const TvSessionGate({super.key});

  @override
  State<TvSessionGate> createState() => _TvSessionGateState();
}

class _TvSessionGateState extends State<TvSessionGate> {
  late final ChannelGatewayApi _api;
  late final TvPairingService _pairingService;
  final TvSessionStorage _storage = TvSessionStorage();
  late final TvSessionRestorer _restorer;

  SessionInfo? _session;
  String? _sessionToken;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ApiConfig.createTvApi();
    _pairingService = TvPairingService(baseUrl: ApiConfig.resolveBaseUrl());
    _restorer = TvSessionRestorer(service: _pairingService, storage: _storage);
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _restorer.restore();
    if (!mounted) return;
    setState(() {
      _session = result.session;
      _sessionToken = result.token;
      _error = result.error;
      _loading = false;
    });
  }

  Future<void> _handleLinked(String token) async {
    try {
      await _storage.saveToken(token);
      final session = await _pairingService.fetchSession(sessionToken: token);
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionToken = token;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
      });
    }
  }

  Future<void> _handleSignOut() async {
    final token = _sessionToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _pairingService.endSession(sessionToken: token);
      } catch (_) {}
    }
    await _storage.clear();
    if (!mounted) return;
    setState(() {
      _session = null;
      _sessionToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SessionLoadingView(
        error: _error,
        onRetry: _restore,
      );
    }
    final session = _session;
    if (session == null) {
      return TvPairingScreen(
        service: _pairingService,
        onLinked: _handleLinked,
      );
    }
    final platform = TvMiniAppPlatform(
      api: _api,
      session: session,
      launchContext: MiniAppLaunchContext(baseUri: Uri()),
      onSignOut: _handleSignOut,
    );
    return MiniAppScreen(platform: platform);
  }
}
