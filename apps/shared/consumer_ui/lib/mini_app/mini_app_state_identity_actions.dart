part of 'mini_app_screen.dart';

mixin MiniAppStateIdentityActions
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateIdentity {
  Future<LinkToken?> _startIdentityLinkRequest({
    required String targetChannel,
    required bool consent,
  }) async {
    final session = _session;
    if (session == null || targetChannel.isEmpty) return null;
    setState(() {
      _linkingIdentity = true;
      _identityError = null;
    });
    try {
      final token = await _api.startIdentityLink(
        sessionId: session.sessionId,
        targetChannel: targetChannel,
        consent: consent,
      );
      if (!mounted) return null;
      setState(() => _linkingIdentity = false);
      return token;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _identityError = e.toString();
        _linkingIdentity = false;
      });
      return null;
    }
  }

  Future<void> _unlinkIdentity(CustomerProfileIdentity identity) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _linkingIdentity = true;
      _identityError = null;
    });
    try {
      final profile = await _api.unlinkIdentity(
        sessionId: session.sessionId,
        channel: identity.channel,
        userId: identity.userId,
      );
      if (!mounted) return;
      setState(() {
        _customerProfile = profile;
        _linkingIdentity = false;
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
