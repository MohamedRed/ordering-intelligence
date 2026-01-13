// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'snapchat_webapp_pkce.dart';
import 'snapchat_webapp_storage.dart';
import 'snapchat_webapp_stub.dart';

class SnapchatWebApp {
  SnapchatWebApp._();

  static bool get isAvailable => true;

  static Future<SnapchatAuthResult?> authorize({
    required String clientId,
    required String redirectUri,
    List<String> scopes = const [],
  }) async {
    final uri = Uri.base;
    final params = Map<String, String>.from(uri.queryParameters);

    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      final description = params['error_description'] ?? '';
      clearSnapchatStorage();
      throw Exception('Snapchat OAuth error: $error ${description.trim()}'.trim());
    }

    final code = params['code'];
    if (code != null && code.trim().isNotEmpty) {
      final state = params['state'] ?? '';
      final storedState = readSnapchatState() ?? '';
      if (storedState.isNotEmpty && storedState != state) {
        clearSnapchatStorage();
        throw Exception('Snapchat OAuth state mismatch.');
      }
      final verifier = readSnapchatVerifier() ?? '';
      final storedRedirect = readSnapchatRedirect() ?? redirectUri;
      restoreSnapchatQuery(uri, params);
      clearSnapchatStorage();
      return SnapchatAuthResult(
        code: code,
        codeVerifier: verifier,
        redirectUri: storedRedirect,
      );
    }

    final verifier = generateSnapchatVerifier();
    final challenge = snapchatCodeChallenge(verifier);
    final state = generateSnapchatState();
    storeOriginalSnapchatQuery(params);
    storeSnapchatState(state);
    storeSnapchatVerifier(verifier);
    storeSnapchatRedirect(redirectUri);

    final authScopes = resolveSnapchatScopes(scopes);
    final authUri = buildSnapchatAuthUri(
      clientId: clientId,
      redirectUri: redirectUri,
      scopes: authScopes,
      state: state,
      challenge: challenge,
    );

    html.window.location.assign(authUri.toString());
    return null;
  }
}
