// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

const _stateStorageKey = 'snapchat_oauth_state';
const _verifierStorageKey = 'snapchat_oauth_verifier';
const _redirectStorageKey = 'snapchat_oauth_redirect';
const _queryStorageKey = 'snapchat_oauth_query';

String? readSnapchatStorage(String key) => html.window.sessionStorage[key];

void writeSnapchatStorage(String key, String value) {
  html.window.sessionStorage[key] = value;
}

void clearSnapchatStorage() {
  html.window.sessionStorage.remove(_stateStorageKey);
  html.window.sessionStorage.remove(_verifierStorageKey);
  html.window.sessionStorage.remove(_redirectStorageKey);
  html.window.sessionStorage.remove(_queryStorageKey);
}

String? readSnapchatState() => readSnapchatStorage(_stateStorageKey);

String? readSnapchatVerifier() => readSnapchatStorage(_verifierStorageKey);

String? readSnapchatRedirect() => readSnapchatStorage(_redirectStorageKey);

void storeSnapchatState(String value) => writeSnapchatStorage(_stateStorageKey, value);

void storeSnapchatVerifier(String value) =>
    writeSnapchatStorage(_verifierStorageKey, value);

void storeSnapchatRedirect(String value) =>
    writeSnapchatStorage(_redirectStorageKey, value);

void storeOriginalSnapchatQuery(Map<String, String> params) {
  final sanitized = stripSnapchatAuthParams(params);
  html.window.sessionStorage[_queryStorageKey] = jsonEncode(sanitized);
}

void restoreSnapchatQuery(Uri uri, Map<String, String> params) {
  final stored = html.window.sessionStorage[_queryStorageKey];
  Map<String, String> target = stripSnapchatAuthParams(params);
  if (stored != null && stored.isNotEmpty) {
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        target = decoded.map((key, value) => MapEntry('$key', '$value'));
      }
    } catch (_) {}
  }
  final replaced = uri.replace(queryParameters: target);
  if (replaced.toString() != uri.toString()) {
    html.window.history.replaceState(null, '', replaced.toString());
  }
}

Map<String, String> stripSnapchatAuthParams(Map<String, String> params) {
  final cleaned = Map<String, String>.from(params);
  cleaned.remove('code');
  cleaned.remove('state');
  cleaned.remove('error');
  cleaned.remove('error_description');
  return cleaned;
}
