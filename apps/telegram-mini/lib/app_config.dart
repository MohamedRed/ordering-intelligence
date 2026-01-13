String resolveApiBase() {
  const dartDefine = String.fromEnvironment('CHANNEL_GATEWAY_BASE_URL');
  if (dartDefine.isNotEmpty) {
    return dartDefine;
  }
  if (_isDiscordContext()) {
    return Uri.base.origin;
  }
  final param = Uri.base.queryParameters['apiBase'];
  if (param != null && param.isNotEmpty) {
    return param;
  }
  return 'https://channel-gateway-230152279015.us-central1.run.app';
}

String resolveWebAppPathPrefix() {
  final params = Uri.base.queryParameters;
  if (_isDiscordContext()) {
    return '/discord/webapp';
  }
  final platform = params['platform']?.toLowerCase().trim();
  if (platform == 'snapchat') {
    return '/snapchat/webapp';
  }
  if (params.containsKey('code') && params.containsKey('state')) {
    return '/snapchat/webapp';
  }
  return '/telegram/webapp';
}

bool _isDiscordContext() {
  final params = Uri.base.queryParameters;
  final platform = params['platform']?.toLowerCase().trim();
  final host = Uri.base.host.toLowerCase();
  return platform == 'discord' ||
      params.containsKey('frame_id') ||
      params.containsKey('frameId') ||
      host.endsWith('discordsays.com');
}

String resolveDiscordClientId() {
  const dartDefine = String.fromEnvironment('DISCORD_CLIENT_ID');
  if (dartDefine.isNotEmpty) {
    return dartDefine;
  }
  final param = Uri.base.queryParameters['discordAppId'];
  if (param != null && param.isNotEmpty) {
    return param;
  }
  return '1457874399339347988';
}

String resolveDiscordRedirectUri() {
  const dartDefine = String.fromEnvironment('DISCORD_REDIRECT_URI');
  if (dartDefine.isNotEmpty) {
    return dartDefine;
  }
  final param = Uri.base.queryParameters['discordRedirectUri'];
  if (param != null && param.isNotEmpty) {
    return param;
  }
  if (_isDiscordContext()) {
    return 'https://telegram-mini-oi2.web.app/';
  }
  final base = Uri.base;
  final params = Map<String, String>.from(base.queryParameters);
  params.remove('code');
  params.remove('state');
  params.remove('error');
  params.remove('error_description');
  return base.replace(queryParameters: params).toString();
}

String resolveSnapchatClientId() {
  const dartDefine = String.fromEnvironment('SNAPCHAT_CLIENT_ID');
  if (dartDefine.isNotEmpty) {
    return dartDefine;
  }
  final param = Uri.base.queryParameters['snapchatClientId'];
  if (param != null && param.isNotEmpty) {
    return param;
  }
  return '';
}

String resolveSnapchatRedirectUri() {
  const dartDefine = String.fromEnvironment('SNAPCHAT_REDIRECT_URI');
  if (dartDefine.isNotEmpty) {
    return dartDefine;
  }
  final param = Uri.base.queryParameters['snapchatRedirectUri'];
  if (param != null && param.isNotEmpty) {
    return param;
  }
  final base = Uri.base;
  final params = Map<String, String>.from(base.queryParameters);
  params.remove('code');
  params.remove('state');
  params.remove('error');
  params.remove('error_description');
  return base.replace(queryParameters: params).toString();
}
