class DiscordAuthResult {
  final String code;
  final String redirectUri;
  final String accessToken;

  const DiscordAuthResult({
    required this.code,
    required this.redirectUri,
    required this.accessToken,
  });
}

class DiscordWebApp {
  DiscordWebApp._();

  static bool get isAvailable => false;

  static Future<DiscordAuthResult> authorize({
    required String clientId,
    List<String> scopes = const ['identify'],
    String? redirectUri,
  }) async {
    throw UnsupportedError('Discord WebApp not available');
  }
}
