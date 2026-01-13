import 'package:consumer_core/consumer_core.dart';

class OAuthProviderConfig {
  final AuthProvider provider;
  final String clientId;
  final String clientIdParam;
  final Uri authorizationEndpoint;
  final String redirectUri;
  final List<String> scopes;
  final bool usePkce;
  final String codeChallengeMethod;
  final Map<String, String> extraAuthParams;

  const OAuthProviderConfig({
    required this.provider,
    required this.clientId,
    this.clientIdParam = 'client_id',
    required this.authorizationEndpoint,
    required this.redirectUri,
    required this.scopes,
    this.usePkce = true,
    this.codeChallengeMethod = 'S256',
    this.extraAuthParams = const {},
  });

  bool get isConfigured => clientId.isNotEmpty && redirectUri.isNotEmpty;
}

class OAuthAuthorizationResult {
  final String code;
  final String state;
  final String codeVerifier;
  final String redirectUri;

  const OAuthAuthorizationResult({
    required this.code,
    required this.state,
    required this.codeVerifier,
    required this.redirectUri,
  });
}
