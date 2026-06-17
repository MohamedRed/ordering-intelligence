import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/widgets.dart';

import '../adapters/mobile_notifications_adapter.dart';
import '../adapters/mobile_payments_adapter.dart';
import '../services/mobile_session_auth.dart';
import 'mobile_audio_recorder.dart';
import 'mobile_haptics.dart';
import 'mobile_share_links.dart';

class MobileMiniAppPlatform extends MiniAppPlatform {
  static const _shareLinks = MobileShareLinks(
    facebookAppId: String.fromEnvironment('FACEBOOK_APP_ID'),
  );

  MobileMiniAppPlatform({
    required ChannelGatewayApi api,
    required SessionInfo session,
    required MiniAppLaunchContext launchContext,
    MobilePaymentsAdapter? paymentsAdapter,
    MobileNotificationsAdapter? notifications,
    MobileSessionAuth? authSigner,
    Future<void> Function()? onSignOut,
  }) : _api = api,
       _session = session,
       _launchContext = launchContext,
       _authSigner = authSigner ?? MobileSessionAuth.fromEnvironment(),
       _paymentsAdapter =
           paymentsAdapter ??
           MobilePaymentsAdapter(
             api: api,
             authSigner: authSigner ?? MobileSessionAuth.fromEnvironment(),
           ),
       _notifications =
           notifications ??
           MobileNotificationsAdapter(
             api: api,
             authSigner: authSigner ?? MobileSessionAuth.fromEnvironment(),
           ),
       _onSignOut = onSignOut;

  final ChannelGatewayApi _api;
  final SessionInfo _session;
  final MiniAppLaunchContext _launchContext;
  final MobileSessionAuth? _authSigner;
  final MobilePaymentsAdapter _paymentsAdapter;
  final MobileNotificationsAdapter _notifications;
  final Future<void> Function()? _onSignOut;

  @override
  ChannelGatewayApi get api => _api;

  @override
  PaymentsAdapter get paymentsAdapter => _paymentsAdapter;

  @override
  MiniAppHaptics get haptics => const MobileHaptics();

  @override
  MiniAppLaunchContext resolveLaunchContext() => _launchContext;

  @override
  Future<SessionInfo?> startSession(MiniAppLaunchContext context) async =>
      _session;

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
  List<MiniAppLinkTarget> linkTargets() => _shareLinks.linkTargets();

  @override
  String labelForChannel(String channel) =>
      _shareLinks.labelForChannel(channel);

  @override
  Uri buildLinkUri({
    required MiniAppLaunchContext context,
    required String targetChannel,
    required String token,
    SessionInfo? session,
  }) => _shareLinks.buildLinkUri(
    context: context,
    targetChannel: targetChannel,
    token: token,
    session: session,
  );

  @override
  void openLink(String channel, Uri uri) => _shareLinks.openLink(channel, uri);

  @override
  Future<void> shareGroupOrderLink(Uri uri, {required String text}) =>
      _shareLinks.shareGroupOrderLink(uri, text: text);

  @override
  List<MiniAppShareTarget> groupOrderShareTargets() =>
      _shareLinks.groupOrderShareTargets();

  @override
  Future<void> shareGroupOrderLinkToTarget(
    MiniAppShareTarget target,
    Uri uri, {
    required String text,
  }) => _shareLinks.shareGroupOrderLinkToTarget(target, uri, text: text);

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
    final signature = _signSession(session);
    return _api.fetchMobilePaymentMethods(
      sessionId: session.sessionId,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }

  @override
  Future<SetupIntentInfo?> createSetupIntent(SessionInfo session) async {
    final signature = _signSession(session);
    return _api.createMobileSetupIntent(
      sessionId: session.sessionId,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
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
    final signature = _signSession(session);
    await _api.setMobileDefaultPaymentMethod(
      sessionId: session.sessionId,
      paymentMethodId: paymentMethodId,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }

  @override
  Future<OffSessionPaymentResult?> payOrderWithDefault({
    required SessionInfo session,
    required String orderId,
    int? amountCents,
    String? currency,
  }) async {
    final signature = _signSession(session);
    return _api.payMobileOrderWithDefault(
      orderId: orderId,
      sessionId: session.sessionId,
      amountCents: amountCents,
      currency: currency,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }

  @override
  Future<PaymentIntentInfo> createGroupOrderPaymentIntent({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    final signature = _signSession(session);
    return _api.createMobileGroupOrderPaymentIntent(
      groupOrderId: groupOrderId,
      sessionId: session.sessionId,
      participantId: participantId,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }

  @override
  Future<OffSessionPaymentResult?> payGroupOrderWithDefault({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    final signature = _signSession(session);
    return _api.payMobileGroupOrderWithDefault(
      groupOrderId: groupOrderId,
      sessionId: session.sessionId,
      participantId: participantId,
      signature: signature?.signature,
      timestamp: signature?.timestamp,
    );
  }

  MobileSessionSignature? _signSession(SessionInfo session) {
    return _authSigner?.signSession(sessionId: session.sessionId);
  }
}
