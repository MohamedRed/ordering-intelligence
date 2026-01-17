part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersItems
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateDrafts {
  Future<void> _submitGroupOrderItems() async {
    final session = _session;
    final groupOrder = _groupOrder;
    if (session == null || groupOrder == null || _cart.isEmpty) return;
    if (groupOrder.status != 'open') {
      setState(() => _orderError = 'Group order is locked.');
      return;
    }
    final participantId = _groupOrderParticipantId ?? session.userId;
    if (participantId.isEmpty) {
      setState(() => _orderError = 'Missing participant.');
      return;
    }
    setState(() {
      _placingOrder = true;
      _orderError = null;
    });
    try {
      final updated = await _api.addGroupOrderItems(
        groupOrderId: groupOrder.id,
        sessionId: session.sessionId,
        participantId: participantId,
        participantLabel: session.displayName,
        items: _cart,
      );
      if (!mounted) return;
      setState(() {
        _groupOrder = updated;
        _placingOrder = false;
        _cart = [];
        _notesController.clear();
      });
      final scope = _currentDraftScope();
      if (scope != null) {
        await _clearDraft(scope);
      }
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _placingOrder = false;
        _orderError = e.toString();
      });
    }
  }
}
