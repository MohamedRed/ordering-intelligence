import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/widgets.dart';

import '../adapters/mobile_payments_adapter.dart';

class TvMiniAppPlatform extends MiniAppPlatform {
  TvMiniAppPlatform({
    required ChannelGatewayApi api,
    required SessionInfo session,
    required MiniAppLaunchContext launchContext,
    Future<void> Function()? onSignOut,
  })  : _api = api,
        _session = session,
        _launchContext = launchContext,
        _paymentsAdapter = MobilePaymentsAdapter(api: api),
        _onSignOut = onSignOut;

  final ChannelGatewayApi _api;
  final SessionInfo _session;
  final MiniAppLaunchContext _launchContext;
  final MobilePaymentsAdapter _paymentsAdapter;
  final Future<void> Function()? _onSignOut;

  @override
  ChannelGatewayApi get api => _api;

  @override
  PaymentsAdapter get paymentsAdapter => _paymentsAdapter;

  @override
  MiniAppHaptics get haptics => const MiniAppHapticsNone();

  @override
  MiniAppLaunchContext resolveLaunchContext() => _launchContext;

  @override
  Future<SessionInfo?> startSession(MiniAppLaunchContext context) async => _session;

  @override
  Future<void> onSessionReady(SessionInfo session) async {}

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
  String currentChannel(MiniAppLaunchContext context) => 'tv';

  @override
  List<MiniAppLinkTarget> linkTargets() => const [];

  @override
  String labelForChannel(String channel) => channel;

  @override
  Uri buildLinkUri({
    required MiniAppLaunchContext context,
    required String targetChannel,
    required String token,
    SessionInfo? session,
  }) {
    return context.baseUri;
  }

  @override
  void openLink(String channel, Uri uri) {}

  @override
  Future<void> shareGroupOrderLink(Uri uri, {required String text}) async {}

  @override
  Future<void> handleOrderUpdates(SessionInfo session, String orderId) async {}

  @override
  String? orderUpdatesLabel(SessionInfo session) => null;

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
  AudioRecorder? createAudioRecorder() => null;

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
}
