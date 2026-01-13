part of 'mini_app_screen.dart';

mixin MiniAppStateGasPumpActions on MiniAppStateGas {
  Future<void> _submitPumpNumber() async {
    final session = _session;
    final order = _orderConfirmation;
    if (session == null || order == null) return;
    final orderId = (order['id'] ?? '').toString().trim();
    if (orderId.isEmpty) return;
    final pumpNumber = _pumpNumberController.text.trim();
    if (pumpNumber.isEmpty) {
      setState(() => _fuelOrderError = 'Enter a pump number.');
      return;
    }
    setState(() => _fuelPumpSubmitting = true);
    try {
      final updated = await _api.setFuelPumpNumber(
        sessionId: session.sessionId,
        orderId: orderId,
        pumpNumber: pumpNumber,
      );
      if (!mounted) return;
      setState(() {
        _fuelPumpSubmitting = false;
        _orderConfirmation = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fuelPumpSubmitting = false;
        _fuelOrderError = e.toString();
      });
    }
  }
}
