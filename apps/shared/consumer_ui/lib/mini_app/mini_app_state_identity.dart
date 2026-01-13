part of 'mini_app_screen.dart';

mixin MiniAppStateIdentity on State<MiniAppScreen>, MiniAppStateFields {
  SessionInfo _withCustomerId(
    SessionInfo session,
    String customerId, {
    int? fuelPreauthCapCents,
  }) {
    return SessionInfo(
      sessionId: session.sessionId,
      accountId: session.accountId,
      userId: session.userId,
      displayName: session.displayName,
      storeId: session.storeId,
      storeName: session.storeName,
      tenantId: session.tenantId,
      customerId: customerId,
      businessType: session.businessType,
      currency: session.currency,
      fuelDefaultPrepayCents: session.fuelDefaultPrepayCents,
      fuelPreauthCapCents: fuelPreauthCapCents ?? session.fuelPreauthCapCents,
      startGroupOrder: session.startGroupOrder,
      telegramBotUsername: session.telegramBotUsername,
    );
  }

  Future<void> _loadIdentity() async {
    final session = _session;
    if (session == null || session.tenantId.isEmpty) {
      return;
    }
    setState(() {
      _loadingIdentity = true;
      _identityError = null;
    });
    try {
      final profile = await _api.fetchIdentity(sessionId: session.sessionId);
      if (!mounted) return;
      final capCents = profile.fuelPreauthCapCents > 0
          ? profile.fuelPreauthCapCents
          : session.fuelPreauthCapCents;
      setState(() {
        _customerProfile = profile;
        _loadingIdentity = false;
        _session = _withCustomerId(
          session,
          profile.customerId,
          fuelPreauthCapCents: capCents,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _identityError = e.toString();
        _loadingIdentity = false;
      });
    }
  }

  Future<void> _completeIdentityLink(String token) async {
    final session = _session;
    if (session == null || token.isEmpty) return;
    setState(() {
      _linkingIdentity = true;
      _identityError = null;
    });
    try {
      final profile = await _api.completeIdentityLink(
        sessionId: session.sessionId,
        token: token,
        consent: true,
      );
      if (!mounted) return;
      final capCents = profile.fuelPreauthCapCents > 0
          ? profile.fuelPreauthCapCents
          : session.fuelPreauthCapCents;
      setState(() {
        _customerProfile = profile;
        _linkingIdentity = false;
        _session = _withCustomerId(
          session,
          profile.customerId,
          fuelPreauthCapCents: capCents,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _identityError = e.toString();
        _linkingIdentity = false;
      });
    }
  }

}
