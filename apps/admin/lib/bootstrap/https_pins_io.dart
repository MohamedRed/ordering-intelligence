import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'pins.dart';

void enforcePinnedCertificates() {
  if (kIsWeb) {
    return;
  }
  HttpOverrides.global = _PinnedHttpOverrides(pinnedCertificates);
}

class _PinnedHttpOverrides extends HttpOverrides {
  _PinnedHttpOverrides(this.allowedPins);

  final Map<String, String> allowedPins;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      final expected = allowedPins[host];
      if (expected == null || expected.isEmpty) {
        return true;
      }
      final fingerprint = sha256.convert(cert.der).toString();
      return fingerprint.toLowerCase() == expected.toLowerCase();
    };
    return client;
  }
}
