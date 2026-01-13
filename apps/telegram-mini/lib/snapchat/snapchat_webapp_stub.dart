class SnapchatAuthResult {
  final String code;
  final String codeVerifier;
  final String redirectUri;

  const SnapchatAuthResult({
    required this.code,
    required this.codeVerifier,
    required this.redirectUri,
  });
}

class SnapchatWebApp {
  SnapchatWebApp._();

  static bool get isAvailable => false;

  static Future<SnapchatAuthResult?> authorize({
    required String clientId,
    required String redirectUri,
    List<String> scopes = const [],
  }) async {
    throw UnsupportedError('Snapchat WebApp not available');
  }
}
