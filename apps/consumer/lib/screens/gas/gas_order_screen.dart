import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import '../../adapters/mobile_payments_adapter.dart';
import '../../models/gas_order_handoff.dart';
import 'gas_order_confirmation.dart';
import 'gas_order_form.dart';
import 'gas_order_store_picker.dart';

class GasOrderScreen extends StatefulWidget {
  const GasOrderScreen({
    super.key,
    required this.session,
    required this.api,
    this.handoff,
  });

  final SessionInfo session;
  final ChannelGatewayApi api;
  final GasOrderHandoff? handoff;

  @override
  State<GasOrderScreen> createState() => _GasOrderScreenState();
}

class _GasOrderScreenState extends State<GasOrderScreen> {
  StoreChoice? _store;
  MenuSnapshot? _menu;
  MenuItem? _selectedGrade;
  FuelPaymentFlow _paymentFlow = FuelPaymentFlow.prepay;
  FuelPrepayMode _prepayMode = FuelPrepayMode.amount;
  String _currency = fuelCurrency;
  int _defaultPrepayCents = 0;
  int _userPreauthCapCents = 0;
  bool _handoffApplied = false;
  bool _preauthEdited = false;

  bool _loadingMenu = false;
  String? _menuError;

  bool _placingOrder = false;
  String? _orderError;
  Map<String, dynamic>? _orderConfirmation;

  bool _pumpSubmitting = false;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _litersController = TextEditingController();
  final TextEditingController _preauthController = TextEditingController();
  final TextEditingController _pumpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrapStore();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _litersController.dispose();
    _preauthController.dispose();
    _pumpController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapStore() async {
    final storeId = widget.handoff?.storeId ?? widget.session.storeId.trim();
    if (storeId.isEmpty) return;
    try {
      final store = await widget.api.fetchStoreDetails(storeId);
      if (store == null) return;
      if (!_isGasStation(store)) return;
      if (!mounted) return;
      setState(() => _store = store);
      await _loadMenu(store.storeId);
    } catch (_) {
      // Ignore session bootstrap failures; user can search manually.
    }
  }

  bool _isGasStation(StoreChoice store) =>
      store.businessType.trim().toLowerCase() == 'gas_station';

  Future<void> _loadMenu(String storeId) async {
    setState(() {
      _loadingMenu = true;
      _menuError = null;
    });
    try {
      final menu = await widget.api.fetchMenu(storeId);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        if (_selectedGrade == null && menu.items.isNotEmpty) {
          _selectedGrade = menu.items.first;
        }
        final store = _store;
        _currency = store?.currency.isNotEmpty == true
            ? store!.currency
            : widget.session.currency.isNotEmpty
                ? widget.session.currency
                : fuelCurrency;
        _defaultPrepayCents =
            store?.fuelDefaultPrepayCents ?? widget.session.fuelDefaultPrepayCents;
        _userPreauthCapCents = widget.session.fuelPreauthCapCents;
        _applyHandoffIfNeeded(menu);
        if (!_handoffApplied && _defaultPrepayCents > 0) {
          final formatted = (_defaultPrepayCents / 100).toStringAsFixed(2);
          if (_amountController.text.isEmpty) {
            _amountController.text = formatted;
          }
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _menuError = err.toString());
    } finally {
      if (mounted) setState(() => _loadingMenu = false);
    }
  }

  void _applyHandoffIfNeeded(MenuSnapshot menu) {
    if (_handoffApplied) return;
    final handoff = widget.handoff;
    if (handoff == null) return;
    final grade = menu.items.firstWhere(
      (item) => item.id == handoff.fuel.fuelGradeId,
      orElse: () => menu.items.first,
    );
    _selectedGrade = grade;
    _paymentFlow = handoff.paymentFlow;
    _prepayMode = handoff.prepayMode;
    if (handoff.fuel.requestedAmountCents > 0) {
      _amountController.text = (handoff.fuel.requestedAmountCents / 100).toStringAsFixed(2);
    }
    if (handoff.fuel.requestedLiters > 0) {
      _litersController.text = handoff.fuel.requestedLiters.toStringAsFixed(2);
    }
    if (handoff.fuel.preauthAmountCents > 0) {
      _preauthController.text = (handoff.fuel.preauthAmountCents / 100).toStringAsFixed(2);
    }
    if (handoff.currency.isNotEmpty) {
      _currency = handoff.currency;
    }
    _handoffApplied = true;
  }

  void _resetOrder() {
    setState(() {
      _orderConfirmation = null;
      _orderError = null;
      _placingOrder = false;
      _pumpSubmitting = false;
    });
    _amountController.clear();
    _litersController.clear();
    _preauthController.clear();
    _pumpController.clear();
    _preauthEdited = false;
  }

  double _parseLiters(String raw) {
    final value = double.tryParse(raw.replaceAll(',', '.').trim());
    return value == null || value.isNaN || value <= 0 ? 0 : value;
  }

  int _parseAmountCents(String raw) {
    final normalized = raw.replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value <= 0) return 0;
    return (value * 100).round();
  }

  int _extractCents(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _placeOrder() async {
    final store = _store;
    final menu = _menu;
    if (store == null || menu == null) return;
    if (!_isGasStation(store)) {
      setState(() => _orderError = 'Select a gas station store to continue.');
      return;
    }
    final grade = _selectedGrade;
    if (grade == null) {
      setState(() => _orderError = 'Select a fuel grade to continue.');
      return;
    }

    final amountCents = _parseAmountCents(_amountController.text);
    final liters = _parseLiters(_litersController.text);
    var preauthCents = _parseAmountCents(_preauthController.text);
    final usedFallbackCap = preauthCents <= 0;
    if (_paymentFlow == FuelPaymentFlow.preauth && preauthCents <= 0) {
      preauthCents = _resolveFuelPreauthCapCents();
    }

    if (_paymentFlow == FuelPaymentFlow.prepay) {
      if (_prepayMode == FuelPrepayMode.amount && amountCents <= 0) {
        setState(() => _orderError = 'Enter a valid amount.');
        return;
      }
      if (_prepayMode == FuelPrepayMode.liters && liters <= 0) {
        setState(() => _orderError = 'Enter liters to prepay.');
        return;
      }
    } else if (preauthCents <= 0) {
      setState(() => _orderError = 'Enter the maximum amount to authorize.');
      return;
    }

    setState(() {
      _placingOrder = true;
      _orderError = null;
    });

    try {
      final fuelDraft = FuelOrderDraft(
        fuelGradeId: grade.id,
        fuelGradeName: grade.name,
        unitPriceCents: grade.priceCents,
        unit: fuelUnitLiter,
        requestedLiters: _prepayMode == FuelPrepayMode.liters ? liters : 0,
        requestedAmountCents:
            _prepayMode == FuelPrepayMode.amount ? amountCents : 0,
        preauthAmountCents:
            _paymentFlow == FuelPaymentFlow.preauth ? preauthCents : 0,
        paymentFlow: _paymentFlow.value,
        pumpNumber: '',
      );
      final response = await widget.api.createOrder(
        sessionId: widget.session.sessionId,
        storeId: store.storeId,
        items: const [],
        fuel: fuelDraft,
        paymentMethod: 'card',
      );

      final orderId = (response['id'] ?? '').toString();
      if (orderId.isEmpty) {
        throw Exception('Order creation failed.');
      }

      final totalCents = _extractCents(response['totalCents']);
      final adapter = MobilePaymentsAdapter(api: widget.api);
      if (_paymentFlow == FuelPaymentFlow.preauth &&
          _preauthEdited &&
          !usedFallbackCap) {
        await _maybeUpdatePreauthCap(preauthCents);
      }
      final intentAmountCents =
          _resolveFuelIntentAmountCents(fuelDraft, totalCents);
      final intent = await adapter.createPaymentIntent(
        orderId: orderId,
        sessionId: widget.session.sessionId,
        amountCents: intentAmountCents > 0 ? intentAmountCents : null,
        currency: _currency.isNotEmpty ? _currency : fuelCurrency,
      );
      if (intent != null) {
        await adapter.confirmPaymentIntent(intent);
      }

      if (!mounted) return;
      setState(() {
        _placingOrder = false;
        _orderConfirmation = response;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _placingOrder = false;
        _orderError = err.toString();
      });
    }
  }

  int _resolveFuelIntentAmountCents(FuelOrderDraft draft, int totalCents) {
    if (draft.paymentFlow.toLowerCase() == FuelPaymentFlow.preauth.value) {
      return draft.preauthAmountCents;
    }
    if (draft.requestedAmountCents > 0) {
      return draft.requestedAmountCents;
    }
    if (draft.requestedLiters > 0 && draft.unitPriceCents > 0) {
      return (draft.requestedLiters * draft.unitPriceCents).round();
    }
    return totalCents;
  }

  int _resolveFuelPreauthCapCents() {
    if (_userPreauthCapCents > 0) return _userPreauthCapCents;
    return _defaultPrepayCents;
  }

  Future<void> _maybeUpdatePreauthCap(int preauthCents) async {
    if (preauthCents <= 0) return;
    final storeDefault = _defaultPrepayCents;
    final current = _userPreauthCapCents;
    final target = storeDefault > 0 && preauthCents == storeDefault ? 0 : preauthCents;
    if (target == current) return;
    try {
      final profile = await widget.api.updateFuelPreauthCap(
        sessionId: widget.session.sessionId,
        fuelPreauthCapCents: target,
      );
      if (!mounted) return;
      setState(() => _userPreauthCapCents = profile.fuelPreauthCapCents);
    } catch (_) {
      // Ignore preference update failures.
    }
  }

  Future<void> _submitPumpNumber() async {
    final order = _orderConfirmation;
    if (order == null) return;
    final orderId = (order['id'] ?? '').toString().trim();
    if (orderId.isEmpty) return;
    final pumpNumber = _pumpController.text.trim();
    if (pumpNumber.isEmpty) {
      setState(() => _orderError = 'Enter a pump number.');
      return;
    }
    setState(() => _pumpSubmitting = true);
    try {
      final updated = await widget.api.setFuelPumpNumber(
        sessionId: widget.session.sessionId,
        orderId: orderId,
        pumpNumber: pumpNumber,
      );
      if (!mounted) return;
      setState(() {
        _pumpSubmitting = false;
        _orderConfirmation = updated;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _pumpSubmitting = false;
        _orderError = err.toString();
      });
    }
  }

  void _clearStore() {
    setState(() {
      _store = null;
      _menu = null;
      _selectedGrade = null;
      _menuError = null;
      _loadingMenu = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel order'),
      ),
      body: Builder(
        builder: (context) {
          if (_orderConfirmation != null) {
            return Center(
              child: GasOrderConfirmation(
                order: _orderConfirmation!,
                pumpController: _pumpController,
                isSubmitting: _pumpSubmitting,
                errorMessage: _orderError,
                onSubmitPump: _submitPumpNumber,
                onNewOrder: _resetOrder,
              ),
            );
          }

          if (store == null || !_isGasStation(store)) {
            return GasOrderStorePicker(
              api: widget.api,
              session: widget.session,
              onStoreSelected: (selected) {
                setState(() => _store = selected);
                _loadMenu(selected.storeId);
              },
            );
          }

          if (_loadingMenu) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_menuError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Unable to load menu: $_menuError'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _loadMenu(store.storeId),
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _clearStore,
                      child: const Text('Change store'),
                    ),
                  ],
                ),
              ),
            );
          }

          final menu = _menu;
          if (menu == null || menu.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No fuel grades available for this store.'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _clearStore,
                      child: const Text('Change store'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      store.name.isEmpty ? store.storeId : store.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearStore,
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GasOrderForm(
                grades: menu.items,
                selectedGrade: _selectedGrade,
                paymentFlow: _paymentFlow,
                prepayMode: _prepayMode,
                amountController: _amountController,
                litersController: _litersController,
                preauthController: _preauthController,
                preauthHint: _buildPreauthHint(),
                currencyCode: _currency.isNotEmpty ? _currency : fuelCurrency,
                isSubmitting: _placingOrder,
                errorMessage: _orderError,
                onSelectGrade: (grade) => setState(() => _selectedGrade = grade),
                onPaymentFlowChanged: (flow) =>
                    setState(() => _paymentFlow = flow),
                onPrepayModeChanged: (mode) =>
                    setState(() => _prepayMode = mode),
                onPreauthChanged: (_) {
                  if (!_preauthEdited) {
                    setState(() => _preauthEdited = true);
                  }
                },
                onSubmit: _placeOrder,
              ),
            ],
          );
        },
      ),
    );
  }

  String? _buildPreauthHint() {
    final cap = _resolveFuelPreauthCapCents();
    if (cap <= 0) return null;
    final amount = _formatMoney(cap);
    final currencyLabel = _currency.isNotEmpty ? _currency.toUpperCase() : fuelCurrency.toUpperCase();
    return 'Default cap: $currencyLabel $amount';
  }

  String _formatMoney(int cents) => (cents / 100).toStringAsFixed(2);
}
