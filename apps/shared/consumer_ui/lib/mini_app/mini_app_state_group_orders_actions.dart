part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersActions
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateRecommendations {
  Future<void> _createGroupOrder() async {
    final session = _session;
    if (session == null || session.storeId.isEmpty) return;
    setState(() {
      _groupOrderBusy = true;
      _groupOrderError = null;
    });
    try {
      final created = await _api.createGroupOrder(
        sessionId: session.sessionId,
        storeId: session.storeId,
        paymentMode: _groupOrderPaymentMode,
        paymentMethod: _groupOrderPaymentMethod,
      );
      if (!mounted) return;
      setState(() {
        _groupOrder = created;
        _groupOrderParticipantId = session.userId;
        _groupOrderSelectedParticipantId = session.userId;
        _groupOrderCollapsed = false;
        if (created.paymentMode.isNotEmpty) {
          _groupOrderPaymentMode = created.paymentMode;
        }
        if (created.paymentMethod.isNotEmpty) {
          _groupOrderPaymentMethod = created.paymentMethod;
        }
        _latestInviteId = null;
        _groupOrderBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupOrderError = e.toString();
        _groupOrderBusy = false;
      });
    }
  }

  Future<void> _submitGroupOrder() async {
    final session = _session;
    final groupOrder = _groupOrder;
    if (session == null || groupOrder == null) return;
    setState(() {
      _groupOrderBusy = true;
      _groupOrderError = null;
    });
    try {
      final updated = await _api.submitGroupOrder(
        groupOrderId: groupOrder.id,
        sessionId: session.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _groupOrder = updated;
        _groupOrderBusy = false;
      });
      await _loadRecommendedOrders();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupOrderError = e.toString();
        _groupOrderBusy = false;
      });
    }
  }
}
