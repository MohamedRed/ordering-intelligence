import 'dart:async';

import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../adapters/mobile_notifications_adapter.dart';
import '../adapters/mobile_payments_adapter.dart';
import 'mobile_audio_recorder.dart';

class MobileMiniAppPlatform extends MiniAppPlatform {
  static const _facebookAppId = String.fromEnvironment('FACEBOOK_APP_ID');

  MobileMiniAppPlatform({
    required ChannelGatewayApi api,
    required SessionInfo session,
    required MiniAppLaunchContext launchContext,
    MobilePaymentsAdapter? paymentsAdapter,
    MobileNotificationsAdapter? notifications,
    Future<void> Function()? onSignOut,
  })  : _api = api,
        _session = session,
        _launchContext = launchContext,
        _paymentsAdapter = paymentsAdapter ?? MobilePaymentsAdapter(api: api),
        _notifications = notifications ?? MobileNotificationsAdapter(api: api),
        _onSignOut = onSignOut;

  final ChannelGatewayApi _api;
  final SessionInfo _session;
  final MiniAppLaunchContext _launchContext;
  final MobilePaymentsAdapter _paymentsAdapter;
  final MobileNotificationsAdapter _notifications;
  final Future<void> Function()? _onSignOut;

  @override
  ChannelGatewayApi get api => _api;

  @override
  PaymentsAdapter get paymentsAdapter => _paymentsAdapter;

  @override
  MiniAppHaptics get haptics => const _MobileHaptics();

  @override
  MiniAppLaunchContext resolveLaunchContext() => _launchContext;

  @override
  Future<SessionInfo?> startSession(MiniAppLaunchContext context) async => _session;

  @override
  Future<void> onSessionReady(SessionInfo session) async {
    await _notifications.registerDevice(
      customerId: session.customerId,
      sessionId: session.sessionId,
    );
  }

  @override
  Future<SessionInfo> refreshSessionForStore({
    required SessionInfo session,
    required String storeId,
    String? locale,
  }) async {
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
  Widget wrapSafeArea(Widget child) => SafeArea(child: child);

  @override
  String currentChannel(MiniAppLaunchContext context) => 'mobile';

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
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  @override
  Future<void> shareGroupOrderLink(Uri uri, {required String text}) async {
    await Share.share('$text\n${uri.toString()}');
  }

  @override
  List<MiniAppShareTarget> groupOrderShareTargets() {
    return [
      const MiniAppShareTarget(id: 'system', label: 'Share'),
      const MiniAppShareTarget(id: 'telegram', label: 'Telegram'),
      const MiniAppShareTarget(id: 'whatsapp', label: 'WhatsApp'),
      if (_facebookAppId.isNotEmpty)
        const MiniAppShareTarget(id: 'messenger', label: 'Messenger'),
      const MiniAppShareTarget(id: 'discord', label: 'Discord'),
      const MiniAppShareTarget(id: 'sms', label: 'SMS'),
    ];
  }

  @override
  Future<void> shareGroupOrderLinkToTarget(
    MiniAppShareTarget target,
    Uri uri, {
    required String text,
  }) async {
    final shareText = '$text\n${uri.toString()}';
    switch (target.id) {
      case 'system':
        await shareGroupOrderLink(uri, text: text);
        return;
      case 'telegram':
        await _launchShareUri(_telegramShareUri(uri, text), fallbackText: shareText);
        return;
      case 'whatsapp':
        await _launchShareUri(_whatsAppShareUri(shareText), fallbackText: shareText);
        return;
      case 'messenger':
        await _launchShareUri(_messengerShareUri(uri), fallbackText: shareText);
        return;
      case 'sms':
        await _launchShareUri(_smsShareUri(shareText), fallbackText: shareText);
        return;
      case 'discord':
        await shareGroupOrderLink(uri, text: text);
        return;
      default:
        await shareGroupOrderLink(uri, text: text);
    }
  }

  @override
  Future<void> handleOrderUpdates(SessionInfo session, String orderId) async {
    await _notifications.registerDevice(
      customerId: session.customerId,
      sessionId: session.sessionId,
    );
  }

  @override
  String? orderUpdatesLabel(SessionInfo session) => 'Enable notifications';

  @override
  String? signOutLabel() => _onSignOut == null ? null : 'Sign out';

  @override
  Future<void> signOut() async {
    await _onSignOut?.call();
  }

  @override
  String? resolveRedirectUrl(MiniAppLaunchContext context) => null;

  @override
  Future<void> handleCardPayment({
    required Map<String, dynamic> orderResponse,
    required SessionInfo session,
    int? amountCents,
    String? currency,
  }) async {
    final orderId = (orderResponse['id'] ?? '').toString();
    if (orderId.isEmpty) return;
    final intent = await _paymentsAdapter.createPaymentIntent(
      orderId: orderId,
      sessionId: session.sessionId,
      amountCents: amountCents,
      currency: currency,
    );
    if (intent != null) {
      await _paymentsAdapter.confirmPaymentIntent(intent);
    }
  }

  @override
  AudioRecorder? createAudioRecorder() => MobileAudioRecorder();

  @override
  bool get supportsSavedPayments => true;

  @override
  Future<List<PaymentMethodSummary>> fetchSavedPaymentMethods(
    SessionInfo session,
  ) async {
    return _api.fetchMobilePaymentMethods(sessionId: session.sessionId);
  }

  @override
  Future<SetupIntentInfo?> createSetupIntent(SessionInfo session) async {
    return _api.createMobileSetupIntent(sessionId: session.sessionId);
  }

  @override
  Future<void> confirmSetupIntent(SetupIntentInfo intent) async {
    await _paymentsAdapter.confirmSetupIntent(intent);
  }

  @override
  Future<void> setDefaultPaymentMethod(
    SessionInfo session,
    String paymentMethodId,
  ) async {
    await _api.setMobileDefaultPaymentMethod(
      sessionId: session.sessionId,
      paymentMethodId: paymentMethodId,
    );
  }

  @override
  Future<OffSessionPaymentResult?> payOrderWithDefault({
    required SessionInfo session,
    required String orderId,
    int? amountCents,
    String? currency,
  }) async {
    return _api.payMobileOrderWithDefault(
      orderId: orderId,
      sessionId: session.sessionId,
      amountCents: amountCents,
      currency: currency,
    );
  }

  @override
  Future<PaymentIntentInfo> createGroupOrderPaymentIntent({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    return _api.createMobileGroupOrderPaymentIntent(
      groupOrderId: groupOrderId,
      sessionId: session.sessionId,
      participantId: participantId,
    );
  }

  @override
  Future<OffSessionPaymentResult?> payGroupOrderWithDefault({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    return _api.payMobileGroupOrderWithDefault(
      groupOrderId: groupOrderId,
      sessionId: session.sessionId,
      participantId: participantId,
    );
  }

  Uri _telegramShareUri(Uri inviteUri, String text) {
    return Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(inviteUri.toString())}&text=${Uri.encodeComponent(text)}',
    );
  }

  Uri _whatsAppShareUri(String text) {
    return Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  }

  Uri _messengerShareUri(Uri inviteUri) {
    final params = {
      'link': inviteUri.toString(),
      'app_id': _facebookAppId,
    };
    return Uri(
      scheme: 'fb-messenger',
      host: 'share',
      queryParameters: params,
    );
  }

  Uri _smsShareUri(String text) {
    return Uri(
      scheme: 'sms',
      queryParameters: {'body': text},
    );
  }

  Future<void> _launchShareUri(
    Uri uri, {
    required String fallbackText,
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await Share.share(fallbackText);
    }
  }
}

class _MobileHaptics extends MiniAppHaptics {
  const _MobileHaptics();

  @override
  void selection() {
    HapticFeedback.selectionClick();
  }

  @override
  void impact({String style = 'light'}) {
    switch (style) {
      case 'medium':
        HapticFeedback.mediumImpact();
        break;
      case 'heavy':
        HapticFeedback.heavyImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }
}
