// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:consumer_ui/utils/audio_recorder.dart' as audio;
import 'package:flutter/widgets.dart';

import '../app_config.dart';
import '../discord/discord_webapp.dart';
import '../platform/web_payments_adapter.dart';
import '../snapchat/snapchat_webapp.dart';
import '../snapchat/snapchat_webapp_storage.dart';
import '../telegram/telegram_safe_area.dart';
import '../telegram/telegram_webapp.dart';
import '../telegram/telegram_webapp_links.dart';

class WebMiniAppPlatform extends MiniAppPlatform {
  WebMiniAppPlatform({
    ChannelGatewayApi? api,
    PaymentsAdapter? paymentsAdapter,
  })  : _api = api ??
            ChannelGatewayApi(
              baseUrl: resolveApiBase(),
              webappPathPrefix: resolveWebAppPathPrefix(),
            ),
        _paymentsAdapter = paymentsAdapter ?? WebPaymentsAdapter();

  final ChannelGatewayApi _api;
  final PaymentsAdapter _paymentsAdapter;
  final MiniAppHaptics _haptics = const _TelegramHaptics();

  @override
  ChannelGatewayApi get api => _api;

  @override
  PaymentsAdapter get paymentsAdapter => _paymentsAdapter;

  @override
  MiniAppHaptics get haptics => _haptics;

  @override
  MiniAppLaunchContext resolveLaunchContext() {
    final uri = Uri.base;
    final params = uri.queryParameters;
    return MiniAppLaunchContext(
      baseUri: uri,
      storeId: params['storeId'],
      locale: _resolveLocale(uri),
      inviteId: params['inviteId'],
      groupOrderId: params['groupOrderId'],
      joinCode: params['joinCode'],
      linkToken: params['linkToken'] ?? params['link_token'],
      startGroupOrder: _parseBoolParam(
        params['startGroupOrder'] ?? params['groupOrder'],
      ),
    );
  }

  @override
  Future<SessionInfo?> startSession(MiniAppLaunchContext context) async {
    TelegramWebApp.ready();
    TelegramWebApp.expand();
    TelegramWebApp.disableVerticalSwipes();
    final platform = _platformFromUri(context.baseUri);
    if (platform == _MiniAppPlatformType.discord) {
      final clientId = resolveDiscordClientId();
      if (clientId.isEmpty) {
        throw Exception('Discord client ID not configured.');
      }
      final auth = await DiscordWebApp.authorize(
        clientId: clientId,
        redirectUri: resolveDiscordRedirectUri(),
      ).timeout(const Duration(seconds: 12));
      final accessToken = auth.accessToken.trim();
      if (accessToken.isEmpty && auth.code.trim().isEmpty) {
        throw Exception('Discord authorization failed.');
      }
      return _api.startDiscordSession(
        code: auth.code,
        redirectUri: auth.redirectUri,
        accessToken: accessToken,
        storeId: context.storeId,
        locale: context.locale,
        startGroupOrder: context.startGroupOrder,
      ).timeout(const Duration(seconds: 12));
    }
    if (platform == _MiniAppPlatformType.snapchat) {
      final clientId = resolveSnapchatClientId();
      if (clientId.isEmpty) {
        throw Exception('Snapchat client ID not configured.');
      }
      final auth = await SnapchatWebApp.authorize(
        clientId: clientId,
        redirectUri: resolveSnapchatRedirectUri(),
      );
      if (auth == null) {
        return null;
      }
      if (auth.code.trim().isEmpty || auth.codeVerifier.trim().isEmpty) {
        throw Exception('Snapchat authorization failed.');
      }
      return _api.startSnapchatSession(
        code: auth.code,
        codeVerifier: auth.codeVerifier,
        redirectUri: auth.redirectUri,
        storeId: context.storeId,
        locale: context.locale,
        startGroupOrder: context.startGroupOrder,
      );
    }
    return _api.startSession(
      initData: TelegramWebApp.initData,
      storeId: context.storeId,
      locale: context.locale,
    );
  }

  @override
  Future<void> onSessionReady(SessionInfo session) async {}

  @override
  Future<SessionInfo> refreshSessionForStore({
    required SessionInfo session,
    required String storeId,
    String? locale,
  }) async {
    final platform = _platformFromUri(Uri.base);
    if (platform == _MiniAppPlatformType.telegram) {
      return _api.startSession(
        initData: TelegramWebApp.initData,
        storeId: storeId,
        locale: locale,
      );
    }
    await _api.selectStore(sessionId: session.sessionId, storeId: storeId);
    final store = await _api.fetchStoreDetails(storeId);
    return SessionInfo(
      sessionId: session.sessionId,
      accountId: session.accountId,
      userId: session.userId,
      displayName: session.displayName,
      storeId: storeId,
      storeName: store?.name ?? '',
      tenantId: store?.tenantId ?? '',
      customerId: session.customerId,
      businessType: store?.businessType ?? '',
      currency: store?.currency ?? '',
      fuelDefaultPrepayCents: store?.fuelDefaultPrepayCents ?? 0,
      fuelPreauthCapCents: session.fuelPreauthCapCents,
      startGroupOrder: false,
      telegramBotUsername: session.telegramBotUsername,
    );
  }

  @override
  Widget wrapSafeArea(Widget child) => TelegramSafeArea(child: child);

  @override
  String currentChannel(MiniAppLaunchContext context) {
    final platform = _platformFromUri(context.baseUri);
    if (platform == _MiniAppPlatformType.discord) return 'discord';
    if (platform == _MiniAppPlatformType.snapchat) return 'snapchat';
    return 'telegram';
  }

  @override
  List<MiniAppLinkTarget> linkTargets() => defaultMiniAppLinkTargets;

  @override
  String labelForChannel(String channel) {
    switch (channel.toLowerCase()) {
      case 'discord':
        return 'Discord';
      case 'snapchat':
        return 'Snapchat';
      default:
        return 'Telegram';
    }
  }

  @override
  Uri buildLinkUri({
    required MiniAppLaunchContext context,
    required String targetChannel,
    required String token,
    SessionInfo? session,
  }) {
    final base = context.baseUri;
    final params = Map<String, String>.from(base.queryParameters);
    params['platform'] = targetChannel;
    params['linkToken'] = token;
    if (session != null && session.storeId.isNotEmpty) {
      params['storeId'] = session.storeId;
    }
    params.remove('code');
    params.remove('state');
    params.remove('error');
    params.remove('error_description');
    return base.replace(queryParameters: params);
  }

  @override
  void openLink(String channel, Uri uri) {
    if (channel.toLowerCase() == 'telegram') {
      TelegramWebAppLinks.openTelegramLink(uri.toString());
    } else {
      TelegramWebAppLinks.openLink(uri.toString());
    }
  }

  @override
  Future<void> shareGroupOrderLink(Uri uri, {required String text}) async {
    final shareLink =
        'https://t.me/share/url?url=${Uri.encodeComponent(uri.toString())}&text=${Uri.encodeComponent(text)}';
    TelegramWebAppLinks.openTelegramLink(shareLink);
  }

  @override
  Future<void> handleOrderUpdates(SessionInfo session, String orderId) async {
    await _api.linkTelegramOrderUpdates(
      sessionId: session.sessionId,
      orderId: orderId,
    );
    final botUsername = session.telegramBotUsername.trim();
    if (botUsername.isEmpty) return;
    final cleanUsername = botUsername.replaceAll('@', '').trim();
    final startParam = Uri.encodeComponent('order_$orderId');
    final link = 'https://t.me/$cleanUsername?start=$startParam';
    TelegramWebAppLinks.openTelegramLink(link);
  }

  @override
  String? orderUpdatesLabel(SessionInfo session) {
    if (session.telegramBotUsername.trim().isEmpty) return null;
    return 'Get updates on Telegram';
  }

  @override
  String? signOutLabel() => 'Sign out';

  @override
  Future<void> signOut() async {
    clearSnapchatStorage();
    final uri = Uri.base;
    final cleaned = _stripEphemeralParams(uri);
    if (cleaned.toString() != uri.toString()) {
      html.window.history.replaceState(null, '', cleaned.toString());
    }
    html.window.location.reload();
  }

  @override
  String? resolveRedirectUrl(MiniAppLaunchContext context) {
    return context.baseUri.toString();
  }

  @override
  Future<void> handleCardPayment({
    required Map<String, dynamic> orderResponse,
    required SessionInfo session,
    int? amountCents,
    String? currency,
  }) async {
    final intent = await _paymentsAdapter.startCheckout(
      orderResponse: orderResponse,
    );
    if (intent != null) {
      await _paymentsAdapter.openCheckout(intent);
    }
  }

  @override
  AudioRecorder? createAudioRecorder() => audio.createAudioRecorder();

  String? _resolveLocale(Uri uri) {
    final platform = _platformFromUri(uri);
    if (platform != _MiniAppPlatformType.telegram) {
      return null;
    }
    final data = TelegramWebApp.initDataUnsafe;
    final user = data['user'];
    if (user is Map && user['language_code'] != null) {
      return user['language_code'].toString();
    }
    return null;
  }

  bool _parseBoolParam(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  Uri _stripEphemeralParams(Uri uri) {
    final params = Map<String, String>.from(uri.queryParameters);
    params.remove('code');
    params.remove('state');
    params.remove('error');
    params.remove('error_description');
    params.remove('linkToken');
    params.remove('link_token');
    params.remove('inviteId');
    params.remove('groupOrderId');
    params.remove('joinCode');
    params.remove('startGroupOrder');
    params.remove('groupOrder');
    return uri.replace(queryParameters: params);
  }

  _MiniAppPlatformType _platformFromUri(Uri uri) {
    final params = uri.queryParameters;
    final platform = params['platform']?.toLowerCase().trim();
    final host = uri.host.toLowerCase();
    final isDiscord = platform == 'discord' ||
        params.containsKey('frame_id') ||
        params.containsKey('frameId') ||
        host.endsWith('discordsays.com');
    if (isDiscord) return _MiniAppPlatformType.discord;
    if (platform == 'snapchat' ||
        (params.containsKey('code') && params.containsKey('state'))) {
      return _MiniAppPlatformType.snapchat;
    }
    return _MiniAppPlatformType.telegram;
  }
}

enum _MiniAppPlatformType { telegram, discord, snapchat }

class _TelegramHaptics extends MiniAppHaptics {
  const _TelegramHaptics();

  @override
  void selection() => TelegramWebApp.hapticSelection();

  @override
  void impact({String style = 'light'}) => TelegramWebApp.hapticImpact(style);
}
