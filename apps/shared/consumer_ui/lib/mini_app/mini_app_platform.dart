import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/widgets.dart';

import '../utils/audio_recorder.dart';

class MiniAppLaunchContext {
  const MiniAppLaunchContext({
    required this.baseUri,
    this.storeId,
    this.locale,
    this.inviteId,
    this.groupOrderId,
    this.joinCode,
    this.linkToken,
    this.startGroupOrder = false,
  });

  final Uri baseUri;
  final String? storeId;
  final String? locale;
  final String? inviteId;
  final String? groupOrderId;
  final String? joinCode;
  final String? linkToken;
  final bool startGroupOrder;
}

class MiniAppLinkTarget {
  const MiniAppLinkTarget({required this.channel, required this.label});

  final String channel;
  final String label;
}

class MiniAppShareTarget {
  const MiniAppShareTarget({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

abstract class MiniAppHaptics {
  const MiniAppHaptics();

  void selection();
  void impact({String style = 'light'});
}

class MiniAppHapticsNone extends MiniAppHaptics {
  const MiniAppHapticsNone();

  @override
  void selection() {}

  @override
  void impact({String style = 'light'}) {}
}

abstract class MiniAppPlatform {
  const MiniAppPlatform();

  ChannelGatewayApi get api;
  PaymentsAdapter get paymentsAdapter;
  MiniAppHaptics get haptics;

  MiniAppLaunchContext resolveLaunchContext();

  Future<SessionInfo?> startSession(MiniAppLaunchContext context);

  Future<void> onSessionReady(SessionInfo session);

  Future<SessionInfo> refreshSessionForStore({
    required SessionInfo session,
    required String storeId,
    String? locale,
  });

  Widget wrapSafeArea(Widget child);

  String currentChannel(MiniAppLaunchContext context);

  List<MiniAppLinkTarget> linkTargets();

  String labelForChannel(String channel);

  Uri buildLinkUri({
    required MiniAppLaunchContext context,
    required String targetChannel,
    required String token,
    SessionInfo? session,
  });

  void openLink(String channel, Uri uri);

  Future<void> shareGroupOrderLink(Uri uri, {required String text});

  List<MiniAppShareTarget> groupOrderShareTargets() => const [];

  Future<void> shareGroupOrderLinkToTarget(
    MiniAppShareTarget target,
    Uri uri, {
    required String text,
  }) async {
    await shareGroupOrderLink(uri, text: text);
  }

  Future<void> handleOrderUpdates(SessionInfo session, String orderId);

  String? orderUpdatesLabel(SessionInfo session);

  String? signOutLabel();

  Future<void> signOut();

  String? resolveRedirectUrl(MiniAppLaunchContext context);

  Future<void> handleCardPayment({
    required Map<String, dynamic> orderResponse,
    required SessionInfo session,
    int? amountCents,
    String? currency,
  });

  AudioRecorder? createAudioRecorder();

  bool get supportsSavedPayments => false;

  Future<List<PaymentMethodSummary>> fetchSavedPaymentMethods(SessionInfo session) async {
    return const [];
  }

  Future<SetupIntentInfo?> createSetupIntent(SessionInfo session) async {
    return null;
  }

  Future<void> confirmSetupIntent(SetupIntentInfo intent) async {}

  Future<void> setDefaultPaymentMethod(
    SessionInfo session,
    String paymentMethodId,
  ) async {}

  Future<OffSessionPaymentResult?> payOrderWithDefault({
    required SessionInfo session,
    required String orderId,
    int? amountCents,
    String? currency,
  }) async {
    return null;
  }

  Future<PaymentIntentInfo> createGroupOrderPaymentIntent({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    throw UnimplementedError('Group order payment intent not supported.');
  }

  Future<OffSessionPaymentResult?> payGroupOrderWithDefault({
    required SessionInfo session,
    required String groupOrderId,
    String? participantId,
  }) async {
    return null;
  }
}
