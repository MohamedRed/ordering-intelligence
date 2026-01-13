import 'package:consumer_core/consumer_core.dart';

import 'oauth/oauth_provider.dart';

const _discordAuthEndpoint = 'https://discord.com/oauth2/authorize';
const _snapchatAuthEndpoint = 'https://accounts.snapchat.com/accounts/oauth2/auth';
const _tiktokAuthEndpoint = 'https://www.tiktok.com/v2/auth/authorize/';

const _snapchatScopes = [
  'https://auth.snapchat.com/oauth2/api/user.external_id',
  'https://auth.snapchat.com/oauth2/api/user.display_name',
];

const _discordScopes = ['identify'];
const _tiktokScopes = ['user.info.basic'];

class ProviderRegistry {
  static OAuthProviderConfig? configFor(AuthProvider provider) {
    switch (provider) {
      case AuthProvider.discord:
        return _discordConfig();
      case AuthProvider.snapchat:
        return _snapchatConfig();
      case AuthProvider.tiktok:
        return _tiktokConfig();
      default:
        return null;
    }
  }

  static OAuthProviderConfig _discordConfig() {
    const clientId = String.fromEnvironment('DISCORD_CLIENT_ID');
    const redirectUri = String.fromEnvironment('DISCORD_REDIRECT_URI');
    return OAuthProviderConfig(
      provider: AuthProvider.discord,
      clientId: clientId,
      authorizationEndpoint: Uri.parse(_discordAuthEndpoint),
      redirectUri: redirectUri,
      scopes: _discordScopes,
    );
  }

  static OAuthProviderConfig _snapchatConfig() {
    const clientId = String.fromEnvironment('SNAPCHAT_CLIENT_ID');
    const redirectUri = String.fromEnvironment('SNAPCHAT_REDIRECT_URI');
    return OAuthProviderConfig(
      provider: AuthProvider.snapchat,
      clientId: clientId,
      authorizationEndpoint: Uri.parse(_snapchatAuthEndpoint),
      redirectUri: redirectUri,
      scopes: _snapchatScopes,
    );
  }

  static OAuthProviderConfig _tiktokConfig() {
    const clientKey = String.fromEnvironment('TIKTOK_CLIENT_KEY');
    const redirectUri = String.fromEnvironment('TIKTOK_REDIRECT_URI');
    return OAuthProviderConfig(
      provider: AuthProvider.tiktok,
      clientId: clientKey,
      clientIdParam: 'client_key',
      authorizationEndpoint: Uri.parse(_tiktokAuthEndpoint),
      redirectUri: redirectUri,
      scopes: _tiktokScopes,
    );
  }
}
