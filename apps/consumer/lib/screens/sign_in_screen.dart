import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import '../adapters/mobile_auth_adapter.dart';
import '../adapters/mobile_notifications_adapter.dart';
import '../services/mobile_session_service.dart';
import 'sign_in/sign_in_providers.dart';
import 'sign_in/sign_in_scaffold.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
    this.initialError,
  });

  final ChannelGatewayApi api;
  final ValueChanged<SessionInfo> onSignedIn;
  final String? initialError;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final bool _allowMock =
      const bool.fromEnvironment('ALLOW_MOCK_AUTH', defaultValue: true);
  late final MobileAuthAdapter _authAdapter;
  late final MobileSessionService _sessionService;
  late final MobileNotificationsAdapter _notificationsAdapter;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _authAdapter = MobileAuthAdapter(allowMock: _allowMock);
    _sessionService = MobileSessionService(api: widget.api);
    _notificationsAdapter = MobileNotificationsAdapter(api: widget.api);
    _error = widget.initialError;
  }

  Future<void> _handleSignIn(AuthProvider provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await _authAdapter.signIn(provider);
      if (auth == null) {
        throw Exception('Authentication cancelled.');
      }
      final session = await _sessionService.startSession(auth: auth);
      try {
        await _notificationsAdapter.registerDevice(
          customerId: session.customerId,
          sessionId: session.sessionId,
        );
      } catch (_) {}
      if (!mounted) return;
      widget.onSignedIn(session);
    } catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = SignInProviders.availableProviders(allowMock: _allowMock);
    return SignInScaffold(
      providers: providers,
      loading: _loading,
      error: _error,
      onProviderSelected: _handleSignIn,
    );
  }
}
