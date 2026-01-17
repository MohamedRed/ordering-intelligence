part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersEntry
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateGroupOrdersActions,
        MiniAppStateGroupOrdersHydrate,
        MiniAppStateDrafts {
  Future<bool> _maybeJoinGroupOrderFromUrl() async {
    final inviteId = _pendingInviteId;
    if (inviteId == null || inviteId.isEmpty) {
      return false;
    }
    var groupOrderId = _pendingGroupOrderId;
    setState(() {
      _groupOrderBusy = true;
      _groupOrderError = null;
    });
    try {
      final session = _session;
      if (session == null) return false;
      if (groupOrderId == null || groupOrderId.isEmpty) {
        final joinCode = _pendingJoinCode;
        if (joinCode == null || joinCode.isEmpty) {
          return false;
        }
        final lookup = await _api.lookupGroupOrderByJoinCode(joinCode: joinCode);
        groupOrderId = lookup.id;
      }
      final joined = await _api.joinGroupOrder(
        groupOrderId: groupOrderId,
        sessionId: session.sessionId,
        inviteId: inviteId,
        displayName: session.displayName,
      );
      if (!mounted) return false;
      setState(() {
        _groupOrder = joined;
        _groupOrderParticipantId = session.userId;
        _groupOrderSelectedParticipantId = session.userId;
        _groupOrderCollapsed = false;
        if (joined.paymentMode.isNotEmpty) {
          _groupOrderPaymentMode = joined.paymentMode;
        }
        if (joined.paymentMethod.isNotEmpty) {
          _groupOrderPaymentMethod = joined.paymentMethod;
        }
        _pendingInviteId = null;
        _pendingGroupOrderId = null;
        _pendingJoinCode = null;
        _groupOrderBusy = false;
      });
      await _hydrateGroupOrderStore(joined.storeId);
      await _loadDraftIfAvailable();
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _groupOrderError = e.toString();
        _groupOrderBusy = false;
      });
      return false;
    }
  }

  Future<bool> _maybeStartGroupOrderFromUrl() async {
    if (!_pendingStartGroupOrder) {
      return false;
    }
    if (_pendingInviteId != null && _pendingInviteId!.isNotEmpty) {
      return false;
    }
    final session = _session;
    if (session == null || session.storeId.isEmpty) {
      return false;
    }
    if (_groupOrder != null) {
      _pendingStartGroupOrder = false;
      return false;
    }
    _pendingStartGroupOrder = false;
    await _createGroupOrder();
    return _groupOrder != null;
  }
}
