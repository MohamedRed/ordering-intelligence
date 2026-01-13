part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersCheckout
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStatePayments {
  Future<void> _lockGroupOrder() async {
    final session = _session;
    final groupOrder = _groupOrder;
    if (session == null || groupOrder == null) return;
    setState(() {
      _groupOrderBusy = true;
      _groupOrderError = null;
    });
    try {
      final locked = await _api.lockGroupOrder(
        groupOrderId: groupOrder.id,
        sessionId: session.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _groupOrder = locked;
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

  Future<void> _checkoutGroupOrder({String? participantId}) async {
    final session = _session;
    final groupOrder = _groupOrder;
    if (session == null || groupOrder == null) return;
    if (groupOrder.status != 'locked' && groupOrder.status != 'payment_pending') {
      setState(() => _groupOrderError = 'Group order must be locked first.');
      return;
    }
    setState(() {
      _groupOrderBusy = true;
      _groupOrderError = null;
    });
    try {
      if (_platform.supportsSavedPayments) {
        await _handleGroupOrderPayment(
          groupOrder: groupOrder,
          session: session,
          participantId: participantId,
        );
      } else {
        final redirectUrl =
            _platform.resolveRedirectUrl(_launchContext) ??
                _launchContext.baseUri.toString();
        final checkout = await _api.checkoutGroupOrder(
          groupOrderId: groupOrder.id,
          sessionId: session.sessionId,
          participantId: participantId,
          successUrl: redirectUrl,
          cancelUrl: redirectUrl,
        );
        if (!mounted) return;
        if (checkout.checkoutUrl.isNotEmpty) {
          _platform.openLink('checkout', Uri.parse(checkout.checkoutUrl));
        }
      }
      if (!mounted) return;
      setState(() => _groupOrderBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groupOrderError = e.toString();
        _groupOrderBusy = false;
      });
    }
  }
}
