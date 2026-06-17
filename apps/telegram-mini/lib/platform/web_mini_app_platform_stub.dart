import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';
import 'package:flutter/widgets.dart';

import '../app_config.dart';

class WebMiniAppPlatform extends MiniAppPlatform {
  WebMiniAppPlatform({ChannelGatewayApi? api, PaymentsAdapter? paymentsAdapter})
    : _api = api ?? ChannelGatewayApi(baseUrl: resolveApiBase()),
      _paymentsAdapter = paymentsAdapter ?? _NoopPaymentsAdapter();

  final ChannelGatewayApi _api;
  final PaymentsAdapter _paymentsAdapter;

  @override
  ChannelGatewayApi get api => _api;

  @override
  PaymentsAdapter get paymentsAdapter => _paymentsAdapter;

  @override
  MiniAppHaptics get haptics => const MiniAppHapticsNone();

  @override
  MiniAppLaunchContext resolveLaunchContext() {
    return MiniAppLaunchContext(baseUri: Uri.parse(resolveApiBase()));
  }

  @override
  Future<SessionInfo?> startSession(MiniAppLaunchContext context) async => null;

  @override
  Future<void> onSessionReady(SessionInfo session) async {}

  @override
  Future<SessionInfo> refreshSessionForStore({
    required SessionInfo session,
    required String storeId,
    String? locale,
  }) async {
    return session;
  }

  @override
  Widget wrapSafeArea(Widget child) => child;

  @override
  String currentChannel(MiniAppLaunchContext context) => 'telegram';

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
  String? signOutLabel() => null;

  @override
  Future<void> signOut() async {}

  @override
  String? resolveRedirectUrl(MiniAppLaunchContext context) => null;

  @override
  Future<void> handleCardPayment({
    required Map<String, dynamic> orderResponse,
    required SessionInfo session,
    int? amountCents,
    String? currency,
  }) async {}

  @override
  AudioRecorder? createAudioRecorder() => null;
}

class _NoopPaymentsAdapter extends PaymentsAdapter {
  @override
  Future<CheckoutIntent?> startCheckout({
    required Map<String, dynamic> orderResponse,
  }) async {
    return null;
  }

  @override
  Future<void> openCheckout(CheckoutIntent intent) async {}

  @override
  Future<PaymentIntentInfo?> createPaymentIntent({
    required String orderId,
    required String sessionId,
    int? amountCents,
    String? currency,
    bool? savePaymentMethod,
  }) async {
    return null;
  }

  @override
  Future<void> confirmPaymentIntent(PaymentIntentInfo intent) async {}
}
