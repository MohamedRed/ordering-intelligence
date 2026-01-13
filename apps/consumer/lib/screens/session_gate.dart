import 'dart:async';

import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/material.dart';

import '../adapters/mobile_notifications_adapter.dart';
import '../models/handoff_payload.dart';
import '../platform/mobile_mini_app_platform.dart';
import '../services/api_config.dart';
import '../services/handoff_link.dart';
import '../services/mobile_launch_context.dart';
import '../services/session_restorer.dart';
import '../services/session_storage.dart';
import '../services/session_terminator.dart';
import 'gas/gas_order_screen.dart';
import 'payment/handoff_order_payment_screen.dart';
import 'reorder/handoff_reorder_screen.dart';
import 'session/session_loading_view.dart';
import 'sign_in_screen.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final ChannelGatewayApi _api;
  final SessionStorage _storage = SessionStorage();
  late final MobileNotificationsAdapter _notificationsAdapter;
  late final SessionRestorer _restorer;
  late final SessionTerminator _terminator;
  late final HandoffLinkService _handoffLinks;
  StreamSubscription<HandoffPayload>? _handoffSub;
  HandoffPayload? _pendingHandoff;
  bool _openingHandoff = false;
  bool _loading = true;
  SessionInfo? _session;
  MobileMiniAppPlatform? _miniAppPlatform;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ApiConfig.createApi();
    _notificationsAdapter = MobileNotificationsAdapter(api: _api);
    _restorer = SessionRestorer(
      api: _api,
      storage: _storage,
      notifications: _notificationsAdapter,
    );
    _terminator = SessionTerminator(
      api: _api,
      notifications: _notificationsAdapter,
      storage: _storage,
    );
    _handoffLinks = HandoffLinkService();
    _handoffSub = _handoffLinks.handoffStream().listen(_handleHandoff);
    _bootstrap();
  }

  @override
  void dispose() {
    _handoffSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _restorer.restore();
    if (!mounted) return;
    setState(() {
      _session = result.session;
      _error = result.error;
      _loading = false;
    });
    final session = result.session;
    if (session != null) {
      _initMiniAppPlatform(session);
    }
    await _consumePendingHandoff();
  }

  Future<void> _handleSignedIn(SessionInfo session) async {
    await _storage.save(session);
    if (!mounted) return;
    setState(() {
      _session = session;
    });
    _initMiniAppPlatform(session);
    await _consumePendingHandoff();
  }

  Future<void> _handleSignOut() async {
    final session = _session;
    if (session != null) {
      await _terminator.terminate(session);
    }
    if (!mounted) return;
    setState(() {
      _session = null;
      _miniAppPlatform = null;
    });
  }

  void _initMiniAppPlatform(SessionInfo session) {
    _miniAppPlatform = MobileMiniAppPlatform(
      api: _api,
      session: session,
      launchContext: MobileLaunchContextResolver.resolve(session: session),
      notifications: _notificationsAdapter,
      onSignOut: _handleSignOut,
    );
  }

  void _handleHandoff(HandoffPayload handoff) {
    _pendingHandoff = handoff;
    _openHandoffIfReady();
  }

  Future<void> _consumePendingHandoff() async {
    final handoff = await _handoffLinks.consumePendingBridgeLink();
    if (!mounted) return;
    if (handoff != null) {
      _pendingHandoff = handoff;
      _openHandoffIfReady();
    }
  }

  void _openHandoffIfReady() {
    final session = _session;
    final handoff = _pendingHandoff;
    if (session == null || handoff == null || _openingHandoff) return;
    _openingHandoff = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (handoff.kind == HandoffKind.fuelOrder && handoff.fuel != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GasOrderScreen(
              session: session,
              api: _api,
              handoff: handoff.fuel,
            ),
          ),
        );
      } else if (handoff.kind == HandoffKind.reorder && handoff.reorder != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HandoffReorderScreen(
              session: session,
              api: _api,
              handoff: handoff.reorder!,
            ),
          ),
        );
      } else if (handoff.kind == HandoffKind.orderPayment &&
          handoff.orderPayment != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HandoffOrderPaymentScreen(
              api: _api,
              handoff: handoff.orderPayment!,
            ),
          ),
        );
      }
      _pendingHandoff = null;
      _openingHandoff = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SessionLoadingView(
        error: _error,
        onRetry: _bootstrap,
      );
    }
    if (_session == null) {
      return SignInScreen(
        api: _api,
        onSignedIn: _handleSignedIn,
        initialError: _error,
      );
    }
    final platform = _miniAppPlatform;
    if (platform == null) {
      return SessionLoadingView(
        error: 'Unable to initialize session.',
        onRetry: _bootstrap,
      );
    }
    return MiniAppScreen(platform: platform);
  }
}
