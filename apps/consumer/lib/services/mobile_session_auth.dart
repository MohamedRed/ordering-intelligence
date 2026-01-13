import 'dart:convert';

import 'package:crypto/crypto.dart';

class MobileSessionSignature {
  final String signature;
  final String timestamp;

  const MobileSessionSignature({
    required this.signature,
    required this.timestamp,
  });
}

class MobileSessionAuth {
  MobileSessionAuth(this._secret);

  final String _secret;

  static MobileSessionAuth? fromEnvironment() {
    const secret = String.fromEnvironment('MOBILE_SESSION_SHARED_SECRET');
    if (secret.isEmpty) {
      return null;
    }
    return MobileSessionAuth(secret);
  }

  MobileSessionSignature? sign({
    required String provider,
    required String subject,
    DateTime? now,
  }) {
    if (_secret.isEmpty) {
      return null;
    }
    final instant = (now ?? DateTime.now().toUtc());
    final timestamp = (instant.millisecondsSinceEpoch ~/ 1000).toString();
    final base = '$provider:$subject:$timestamp';
    final mac = Hmac(sha256, utf8.encode(_secret));
    final digest = mac.convert(utf8.encode(base)).toString();
    return MobileSessionSignature(signature: digest, timestamp: timestamp);
  }

  MobileSessionSignature? signSession({
    required String sessionId,
    DateTime? now,
  }) {
    if (_secret.isEmpty) {
      return null;
    }
    final instant = (now ?? DateTime.now().toUtc());
    final timestamp = (instant.millisecondsSinceEpoch ~/ 1000).toString();
    final base = 'session:$sessionId:$timestamp';
    final mac = Hmac(sha256, utf8.encode(_secret));
    final digest = mac.convert(utf8.encode(base)).toString();
    return MobileSessionSignature(signature: digest, timestamp: timestamp);
  }
}
