import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const snapchatAuthEndpoint =
    'https://accounts.snapchat.com/accounts/oauth2/auth';

const defaultSnapchatScopes = [
  'https://auth.snapchat.com/oauth2/api/user.external_id',
  'https://auth.snapchat.com/oauth2/api/user.display_name',
];

List<String> resolveSnapchatScopes(List<String> scopes) {
  return scopes.isEmpty ? defaultSnapchatScopes : scopes;
}

Uri buildSnapchatAuthUri({
  required String clientId,
  required String redirectUri,
  required List<String> scopes,
  required String state,
  required String challenge,
}) {
  return Uri.parse(snapchatAuthEndpoint).replace(
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    },
  );
}

String generateSnapchatVerifier() {
  final bytes = List<int>.generate(32, (_) => _randomByte());
  return _base64UrlEncode(bytes);
}

String generateSnapchatState() {
  final bytes = List<int>.generate(16, (_) => _randomByte());
  return _base64UrlEncode(bytes);
}

String snapchatCodeChallenge(String verifier) {
  final hash = sha256.convert(utf8.encode(verifier)).bytes;
  return _base64UrlEncode(hash);
}

int _randomByte() => Random.secure().nextInt(256);

String _base64UrlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
