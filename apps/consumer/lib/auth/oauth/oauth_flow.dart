import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'oauth_pkce.dart';
import 'oauth_provider.dart';

class OAuthFlow {
  Future<OAuthAuthorizationResult> authorize(OAuthProviderConfig config) async {
    if (!config.isConfigured) {
      throw Exception('OAuth provider not configured.');
    }
    final state = generateOAuthState();
    final verifier = config.usePkce ? generateCodeVerifier() : '';
    final challenge = config.usePkce ? codeChallengeS256(verifier) : '';

    final authUri = config.authorizationEndpoint.replace(
      queryParameters: {
        config.clientIdParam: config.clientId,
        'redirect_uri': config.redirectUri,
        'response_type': 'code',
        'scope': config.scopes.join(' '),
        'state': state,
        if (config.usePkce) 'code_challenge': challenge,
        if (config.usePkce) 'code_challenge_method': config.codeChallengeMethod,
        ...config.extraAuthParams,
      },
    );

    final callbackScheme = Uri.parse(config.redirectUri).scheme;
    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: callbackScheme,
    );

    final uri = Uri.parse(result);
    final code = uri.queryParameters['code'] ?? '';
    final returnedState = uri.queryParameters['state'] ?? '';
    if (code.isEmpty || returnedState.isEmpty) {
      throw Exception('OAuth response missing code.');
    }
    if (returnedState != state) {
      throw Exception('OAuth state mismatch.');
    }

    return OAuthAuthorizationResult(
      code: code,
      state: state,
      codeVerifier: verifier,
      redirectUri: config.redirectUri,
    );
  }
}
