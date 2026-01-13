part of 'mini_app_screen.dart';

mixin MiniAppStateGasActions on MiniAppStateGas, MiniAppStatePayments {
  Future<void> _placeFuelOrder() async {
    final session = _session;
    if (session == null || !_isGasStation) return;
    final grade = _selectedFuelGrade;
    if (grade == null) {
      setState(() => _fuelOrderError = 'Select a fuel grade to continue.');
      return;
    }
    final unitPriceCents = grade.priceCents;
    final amountCents = _parseAmountCents(_fuelAmountController.text);
    final liters = _parseLiters(_fuelLitersController.text);
    var preauthCents = _parseAmountCents(_fuelPreauthController.text);
    final usedFallbackCap = preauthCents <= 0;
    if (_fuelPaymentFlow == FuelPaymentFlow.preauth && preauthCents <= 0) {
      preauthCents = _resolveFuelPreauthCapCents();
    }
    if (_fuelPaymentFlow == FuelPaymentFlow.prepay) {
      if (_fuelPrepayMode == FuelPrepayMode.amount && amountCents <= 0) {
        setState(() => _fuelOrderError = 'Enter a valid amount.');
        return;
      }
      if (_fuelPrepayMode == FuelPrepayMode.liters && liters <= 0) {
        setState(() => _fuelOrderError = 'Enter liters to prepay.');
        return;
      }
    } else if (preauthCents <= 0) {
      setState(() => _fuelOrderError = 'Enter the maximum amount to authorize.');
      return;
    }

    setState(() {
      _placingFuelOrder = true;
      _fuelOrderError = null;
    });
    try {
      final fuelDraft = FuelOrderDraft(
        fuelGradeId: grade.id,
        fuelGradeName: grade.name,
        unitPriceCents: unitPriceCents,
        unit: 'liter',
        requestedLiters: _fuelPrepayMode == FuelPrepayMode.liters ? liters : 0,
        requestedAmountCents:
            _fuelPrepayMode == FuelPrepayMode.amount ? amountCents : 0,
        preauthAmountCents:
            _fuelPaymentFlow == FuelPaymentFlow.preauth ? preauthCents : 0,
        paymentFlow: _fuelPaymentFlow.value,
        pumpNumber: '',
      );
      final redirectUrl = _platform.resolveRedirectUrl(_launchContext);
      final result = await _api.createOrder(
        sessionId: session.sessionId,
        storeId: session.storeId,
        items: const [],
        fuel: fuelDraft,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        locale: _locale,
        paymentMethod: 'card',
        successUrl: redirectUrl,
        cancelUrl: redirectUrl,
      );
      if (!mounted) return;
      setState(() {
        _placingFuelOrder = false;
        _orderConfirmation = result;
      });
      if (_fuelPaymentFlow == FuelPaymentFlow.preauth &&
          _fuelPreauthEdited &&
          !usedFallbackCap) {
        await _maybeUpdateFuelPreauthCap(preauthCents);
      }
      await _handleOrderPayment(
        orderResponse: result,
        session: session,
        amountCents: _resolveFuelIntentAmountCents(fuelDraft),
        currency: session.currency.isNotEmpty ? session.currency : fuelCurrency,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _placingFuelOrder = false;
        _fuelOrderError = e.toString();
      });
    }
  }

  int? _resolveFuelIntentAmountCents(FuelOrderDraft draft) {
    final flow = draft.paymentFlow.toLowerCase();
    if (flow == FuelPaymentFlow.preauth.value) {
      return draft.preauthAmountCents > 0 ? draft.preauthAmountCents : null;
    }
    if (draft.requestedAmountCents > 0) {
      return draft.requestedAmountCents;
    }
    if (draft.requestedLiters > 0 && draft.unitPriceCents > 0) {
      return (draft.requestedLiters * draft.unitPriceCents).round();
    }
    return null;
  }

  Future<void> _maybeUpdateFuelPreauthCap(int preauthCents) async {
    final session = _session;
    if (session == null || preauthCents <= 0) return;
    final storeDefault = session.fuelDefaultPrepayCents;
    final current = session.fuelPreauthCapCents;
    final target = storeDefault > 0 && preauthCents == storeDefault ? 0 : preauthCents;
    if (target == current) return;
    try {
      final profile = await _api.updateFuelPreauthCap(
        sessionId: session.sessionId,
        fuelPreauthCapCents: target,
      );
      if (!mounted) return;
      setState(() {
        _customerProfile = profile;
        _session = SessionInfo(
          sessionId: session.sessionId,
          accountId: session.accountId,
          userId: session.userId,
          displayName: session.displayName,
          storeId: session.storeId,
          storeName: session.storeName,
          tenantId: session.tenantId,
          customerId: session.customerId,
          businessType: session.businessType,
          currency: session.currency,
          fuelDefaultPrepayCents: session.fuelDefaultPrepayCents,
          fuelPreauthCapCents: profile.fuelPreauthCapCents,
          startGroupOrder: session.startGroupOrder,
          telegramBotUsername: session.telegramBotUsername,
        );
      });
    } catch (_) {
      // Ignore preference update failures.
    }
  }
}
