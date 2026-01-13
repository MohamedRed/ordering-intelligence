enum AuthProvider {
  telegram,
  discord,
  snapchat,
  facebook,
  tiktok,
}

extension AuthProviderLabel on AuthProvider {
  String get id {
    switch (this) {
      case AuthProvider.telegram:
        return 'telegram';
      case AuthProvider.discord:
        return 'discord';
      case AuthProvider.snapchat:
        return 'snapchat';
      case AuthProvider.facebook:
        return 'facebook';
      case AuthProvider.tiktok:
        return 'tiktok';
    }
  }

  String get displayLabel {
    switch (this) {
      case AuthProvider.telegram:
        return 'Telegram';
      case AuthProvider.discord:
        return 'Discord';
      case AuthProvider.snapchat:
        return 'Snapchat';
      case AuthProvider.facebook:
        return 'Facebook';
      case AuthProvider.tiktok:
        return 'TikTok';
    }
  }
}

class AuthSession {
  final AuthProvider provider;
  final String subject;
  final String displayName;
  final String? accessToken;
  final String? authCode;
  final String? codeVerifier;
  final String? redirectUri;
  final Map<String, String> metadata;

  const AuthSession({
    required this.provider,
    required this.subject,
    required this.displayName,
    this.accessToken,
    this.authCode,
    this.codeVerifier,
    this.redirectUri,
    this.metadata = const {},
  });
}

abstract class AuthAdapter {
  Future<AuthSession?> signIn(AuthProvider provider);
}
