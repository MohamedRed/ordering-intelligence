import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MobileClientInfo {
  final String platform;
  final String app;
  final String version;
  final String os;
  final String osVersion;

  const MobileClientInfo({
    required this.platform,
    required this.app,
    required this.version,
    required this.os,
    required this.osVersion,
  });

  factory MobileClientInfo.fromEnvironment() {
    const appId = String.fromEnvironment(
      'CONSUMER_APP_ID',
      defaultValue: 'consumer-mobile',
    );
    const version = String.fromEnvironment('CONSUMER_APP_VERSION');
    final platform = kIsWeb
        ? 'web'
        : Platform.isIOS
            ? 'ios'
            : Platform.isAndroid
                ? 'android'
                : 'mobile';
    return MobileClientInfo(
      platform: platform,
      app: appId,
      version: version,
      os: kIsWeb ? 'web' : Platform.operatingSystem,
      osVersion: kIsWeb ? '' : Platform.operatingSystemVersion,
    );
  }

  Future<String> resolveVersion() async {
    if (version.isNotEmpty) return version;
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
