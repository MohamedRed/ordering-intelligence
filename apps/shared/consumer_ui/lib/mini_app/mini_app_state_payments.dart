part of 'mini_app_screen.dart';

mixin MiniAppStatePayments on State<MiniAppScreen>, MiniAppStateFields {
  bool _loadingPaymentMethods = false;
  String? _paymentMethodsError;
  List<PaymentMethodSummary> _paymentMethods = const [];
  bool _oneTapEnabled = false;
  bool _oneTapInitialized = false;

  bool get _supportsSavedPayments => _platform.supportsSavedPayments;

  PaymentMethodSummary? get _defaultPaymentMethod {
    try {
      return _paymentMethods.firstWhere((method) => method.isDefault);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPaymentMethods({bool silent = false}) async {
    if (!_supportsSavedPayments) return;
    final session = _session;
    if (session == null) return;
    if (!silent) {
      setState(() {
        _loadingPaymentMethods = true;
        _paymentMethodsError = null;
      });
    }
    try {
      final methods = await _platform.fetchSavedPaymentMethods(session);
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _loadingPaymentMethods = false;
        if (!_oneTapInitialized) {
          _oneTapEnabled = methods.any((method) => method.isDefault);
          _oneTapInitialized = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentMethodsError = e.toString();
        _loadingPaymentMethods = false;
      });
    }
  }

  Future<void> _addPaymentMethod() async {
    final session = _session;
    if (!_supportsSavedPayments || session == null) return;
    setState(() {
      _loadingPaymentMethods = true;
      _paymentMethodsError = null;
    });
    try {
      final intent = await _platform.createSetupIntent(session);
      if (intent == null) {
        setState(() => _loadingPaymentMethods = false);
        return;
      }
      await _platform.confirmSetupIntent(intent);
      if (!mounted) return;
      await _loadPaymentMethods(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentMethodsError = e.toString();
        _loadingPaymentMethods = false;
      });
    }
  }

  Future<void> _setDefaultPaymentMethod(String paymentMethodId) async {
    final session = _session;
    if (!_supportsSavedPayments || session == null) return;
    setState(() {
      _loadingPaymentMethods = true;
      _paymentMethodsError = null;
    });
    try {
      await _platform.setDefaultPaymentMethod(session, paymentMethodId);
      if (!mounted) return;
      await _loadPaymentMethods(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentMethodsError = e.toString();
        _loadingPaymentMethods = false;
      });
    }
  }

  void _toggleOneTap(bool value) {
    setState(() => _oneTapEnabled = value);
  }

  Widget? _buildPaymentMethodsPanel() {
    if (!_supportsSavedPayments) return null;
    if (_orderPaymentMethod != 'card') return null;
    return PaymentMethodsPanel(
      defaultMethod: _defaultPaymentMethod,
      methodCount: _paymentMethods.length,
      oneTapEnabled: _oneTapEnabled,
      onToggleOneTap: _toggleOneTap,
      onManage: _openPaymentMethodsSheet,
      loading: _loadingPaymentMethods,
      error: _paymentMethodsError,
    );
  }

  Future<void> _openPaymentMethodsSheet() async {
    if (!_supportsSavedPayments) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = ShadTheme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saved cards', style: theme.textTheme.large),
                const SizedBox(height: 12),
                if (_loadingPaymentMethods)
                  const Center(
                    child: CircularProgressIndicator(),
                  )
                else if (_paymentMethods.isEmpty)
                  Text('No cards saved yet.', style: theme.textTheme.muted)
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _paymentMethods.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final method = _paymentMethods[index];
                        final subtitle = method.expiryLabel.isEmpty
                            ? null
                            : 'Exp ${method.expiryLabel}';
                        return ListTile(
                          title: Text(method.maskedLabel),
                          subtitle: subtitle == null ? null : Text(subtitle),
                          trailing: method.isDefault
                              ? const Text('Default')
                              : TextButton(
                                  onPressed: () => _setDefaultPaymentMethod(method.id),
                                  child: const Text('Set default'),
                                ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: _loadingPaymentMethods ? null : _addPaymentMethod,
                  child: const Text('Add card'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleOrderPayment({
    required Map<String, dynamic> orderResponse,
    required SessionInfo session,
    int? amountCents,
    String? currency,
  }) async {
    if (_supportsSavedPayments &&
        _oneTapEnabled &&
        _defaultPaymentMethod != null) {
      try {
        final result = await _platform.payOrderWithDefault(
          session: session,
          orderId: (orderResponse['id'] ?? '').toString(),
          amountCents: amountCents,
          currency: currency,
        );
        if (result != null) {
          if (result.succeeded) return;
          if (result.requiresAction && result.intent != null) {
            await _platform.paymentsAdapter.confirmPaymentIntent(result.intent!);
            return;
          }
        }
      } catch (_) {}
    }
    await _platform.handleCardPayment(
      orderResponse: orderResponse,
      session: session,
      amountCents: amountCents,
      currency: currency,
    );
  }

  Future<void> _handleGroupOrderPayment({
    required GroupOrderSession groupOrder,
    required SessionInfo session,
    String? participantId,
  }) async {
    if (!_supportsSavedPayments) {
      return;
    }
    if (_oneTapEnabled && _defaultPaymentMethod != null) {
      try {
        final result = await _platform.payGroupOrderWithDefault(
          session: session,
          groupOrderId: groupOrder.id,
          participantId: participantId,
        );
        if (result != null) {
          if (result.succeeded) return;
          if (result.requiresAction && result.intent != null) {
            await _platform.paymentsAdapter.confirmPaymentIntent(result.intent!);
            return;
          }
        }
      } catch (_) {}
    }
    final intent = await _platform.createGroupOrderPaymentIntent(
      session: session,
      groupOrderId: groupOrder.id,
      participantId: participantId,
    );
    await _platform.paymentsAdapter.confirmPaymentIntent(intent);
  }
}
