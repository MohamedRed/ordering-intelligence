import 'package:consumer_core/consumer_core.dart';

class SignInProviders {
  static List<AuthProvider> availableProviders({required bool allowMock}) {
    return <AuthProvider>[
      AuthProvider.facebook,
      AuthProvider.discord,
      AuthProvider.snapchat,
      AuthProvider.tiktok,
      AuthProvider.telegram,
    ].where((provider) => allowMock || _isProviderConfigured(provider)).toList();
  }

  static bool _isProviderConfigured(AuthProvider provider) {
    switch (provider) {
      case AuthProvider.facebook:
        return const String.fromEnvironment('FACEBOOK_APP_ID').isNotEmpty;
      case AuthProvider.discord:
        return const String.fromEnvironment('DISCORD_CLIENT_ID').isNotEmpty &&
            const String.fromEnvironment('DISCORD_REDIRECT_URI').isNotEmpty;
      case AuthProvider.snapchat:
        return const String.fromEnvironment('SNAPCHAT_CLIENT_ID').isNotEmpty &&
            const String.fromEnvironment('SNAPCHAT_REDIRECT_URI').isNotEmpty;
      case AuthProvider.tiktok:
        return const String.fromEnvironment('TIKTOK_CLIENT_KEY').isNotEmpty &&
            const String.fromEnvironment('TIKTOK_REDIRECT_URI').isNotEmpty;
      case AuthProvider.telegram:
        return false;
    }
  }
}
