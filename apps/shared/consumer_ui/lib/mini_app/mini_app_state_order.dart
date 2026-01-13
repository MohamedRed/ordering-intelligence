part of 'mini_app_screen.dart';

mixin MiniAppStateOrder
    on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateGas, MiniAppStatePayments {
  Future<void> _placeOrder() async {
    final session = _session;
    if (session == null || session.storeId.isEmpty || _cart.isEmpty) {
      return;
    }
    setState(() {
      _placingOrder = true;
      _orderError = null;
    });
    try {
      final paymentMethod = _orderPaymentMethod;
      final redirectUrl = _platform.resolveRedirectUrl(_launchContext);
      final result = await _api.createOrder(
        sessionId: session.sessionId,
        storeId: session.storeId,
        items: _cart,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        locale: _locale,
        paymentMethod: paymentMethod,
        successUrl: paymentMethod == 'card' ? redirectUrl : null,
        cancelUrl: paymentMethod == 'card' ? redirectUrl : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _placingOrder = false;
        _orderConfirmation = result;
        _cart = [];
        _notesController.clear();
      });
      if (paymentMethod == 'card') {
        await _handleOrderPayment(
          orderResponse: result,
          session: session,
        );
      }
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _placingOrder = false;
        _orderError = e.toString();
      });
    }
  }

  void _resetOrder() {
    setState(() {
      _orderConfirmation = null;
      _orderError = null;
      _cart = [];
      _notesController.clear();
      if (_isGasStation) {
        _resetFuelDraft();
      }
    });
  }

  Future<void> _handleOrderUpdates(String orderId) async {
    final session = _session;
    final trimmedOrderId = orderId.trim();
    if (session == null || trimmedOrderId.isEmpty) {
      return;
    }
    try {
      await _platform.handleOrderUpdates(session, trimmedOrderId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_orderUpdatesLabel ?? 'Updates'} enabled.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to enable updates.')),
      );
    }
  }
}
