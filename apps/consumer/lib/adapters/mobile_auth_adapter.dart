import 'package:consumer_core/consumer_core.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import '../auth/oauth/oauth_flow.dart';
import '../auth/provider_registry.dart';

class MobileAuthAdapter implements AuthAdapter {
  MobileAuthAdapter({required this.allowMock, OAuthFlow? oauthFlow})
      : _oauthFlow = oauthFlow ?? OAuthFlow();

  final bool allowMock;
  final OAuthFlow _oauthFlow;

  @override
  Future<AuthSession?> signIn(AuthProvider provider) async {
    if (allowMock) {
      return AuthSession(
        provider: provider,
        subject: 'dev-${provider.id}',
        displayName: 'Dev User',
      );
    }

    switch (provider) {
      case AuthProvider.facebook:
        return _signInFacebook();
      case AuthProvider.discord:
      case AuthProvider.snapchat:
      case AuthProvider.tiktok:
        return _signInOAuth(provider);
      case AuthProvider.telegram:
        throw UnsupportedError('Telegram mobile login not configured.');
    }
  }

  Future<AuthSession?> _signInOAuth(AuthProvider provider) async {
    final config = ProviderRegistry.configFor(provider);
    if (config == null || !config.isConfigured) {
      throw Exception('${provider.displayLabel} OAuth is not configured.');
    }
    final result = await _oauthFlow.authorize(config);
    return AuthSession(
      provider: provider,
      subject: '',
      displayName: '',
      authCode: result.code,
      codeVerifier: result.codeVerifier,
      redirectUri: result.redirectUri,
    );
  }

  Future<AuthSession?> _signInFacebook() async {
    final result = await FacebookAuth.instance.login(
      permissions: const ['public_profile'],
    );
    if (result.status != LoginStatus.success) {
      return null;
    }
    final token = result.accessToken?.tokenString ?? '';
    if (token.isEmpty) {
      return null;
    }
    final profile = await FacebookAuth.instance.getUserData(fields: 'id,name');
    return AuthSession(
      provider: AuthProvider.facebook,
      subject: (profile['id'] ?? '').toString(),
      displayName: (profile['name'] ?? '').toString(),
      accessToken: token,
    );
  }
}
