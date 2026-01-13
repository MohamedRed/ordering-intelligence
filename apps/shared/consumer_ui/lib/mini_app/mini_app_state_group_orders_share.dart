part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersShare on State<MiniAppScreen>, MiniAppStateFields {
  static const _shareText = 'Join my group order';

  Future<void> _shareGroupOrder() async {
    final shareUri = await _ensureGroupOrderShareUri();
    if (shareUri == null) return;
    await _platform.shareGroupOrderLink(shareUri, text: _shareText);
  }

  Future<void> _shareGroupOrderToTarget(MiniAppShareTarget target) async {
    final shareUri = await _ensureGroupOrderShareUri();
    if (shareUri == null) return;
    await _platform.shareGroupOrderLinkToTarget(
      target,
      shareUri,
      text: _shareText,
    );
  }

  Future<Uri?> _ensureGroupOrderShareUri({bool createIfMissing = true}) async {
    final order = _groupOrder;
    final session = _session;
    if (order == null || session == null) return null;
    var inviteId = _latestInviteId;
    if (inviteId == null || inviteId.isEmpty) {
      if (!createIfMissing) return null;
      setState(() {
        _groupOrderBusy = true;
        _groupOrderError = null;
      });
      try {
        final invite = await _api.createGroupOrderInvite(
          groupOrderId: order.id,
          sessionId: session.sessionId,
        );
        if (!mounted) return null;
        inviteId = invite.inviteId;
        setState(() {
          _latestInviteId = inviteId;
          _groupOrderBusy = false;
        });
      } catch (e) {
        if (!mounted) return null;
        setState(() {
          _groupOrderError = e.toString();
          _groupOrderBusy = false;
        });
        return null;
      }
    }
    return _buildGroupOrderShareUri(order, inviteId);
  }

  Uri _buildGroupOrderShareUri(GroupOrderSession order, String inviteId) {
    final current = _launchContext.baseUri;
    final params = Map<String, String>.from(current.queryParameters);
    params['inviteId'] = inviteId;
    params['groupOrderId'] = order.id;
    if (order.storeId.isNotEmpty) {
      params['storeId'] = order.storeId;
    }
    return current.replace(queryParameters: params);
  }
}
