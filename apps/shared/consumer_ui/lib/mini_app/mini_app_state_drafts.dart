part of 'mini_app_screen.dart';

class _DraftScope {
  const _DraftScope({
    required this.storeId,
    required this.orderType,
    required this.groupOrderId,
  });

  final String storeId;
  final String orderType;
  final String groupOrderId;

  String get key {
    final group = groupOrderId.isEmpty ? 'single' : groupOrderId;
    return '$storeId|$orderType|$group';
  }
}

mixin MiniAppStateDrafts
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateDelivery {
  Timer? _draftSaveDebounce;
  String _draftScopeKey = '';
  int _draftVersion = 0;
  DraftOrder? _latestDraft;
  bool _draftPrompted = false;
  bool _draftRestoring = false;

  void _initDraftObservers() {
    _notesController.addListener(_scheduleDraftSave);
    _deliveryAddressController.addListener(_scheduleDraftSave);
    _deliveryInstructionsController.addListener(_scheduleDraftSave);
  }

  @override
  void _onDraftRelevantChange() {
    _scheduleDraftSave();
  }

  void _disposeDraftObservers() {
    _draftSaveDebounce?.cancel();
  }

  void _resetDraftContext() {
    _draftScopeKey = '';
    _draftVersion = 0;
    _latestDraft = null;
    _draftPrompted = false;
  }

  _DraftScope? _currentDraftScope() {
    final session = _session;
    if (session == null || session.storeId.isEmpty) return null;
    final group = _groupOrder;
    if (group != null) {
      return _DraftScope(
        storeId: session.storeId,
        orderType: 'group',
        groupOrderId: group.id,
      );
    }
    return _DraftScope(
      storeId: session.storeId,
      orderType: 'single',
      groupOrderId: '',
    );
  }

  bool _hasLocalDraftData() {
    return _cart.isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _deliveryAddressController.text.trim().isNotEmpty ||
        _deliveryInstructionsController.text.trim().isNotEmpty;
  }

  void _scheduleDraftSave() {
    if (_draftRestoring) return;
    final scope = _currentDraftScope();
    if (scope == null) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 900), () {
      _saveDraft(scope);
    });
  }

  Future<void> _saveDraft(_DraftScope scope) async {
    final session = _session;
    if (session == null) return;
    final items = DraftOrderLogic.itemsFromCart(_cart);
    final delivery = _buildDraftDelivery();
    final draft = DraftOrder(
      id: '',
      storeId: scope.storeId,
      orderType: scope.orderType,
      groupOrderId: scope.groupOrderId,
      fulfillmentType: _fulfillmentType,
      notes: _notesController.text.trim(),
      items: items,
      delivery: delivery,
      version: _draftVersion,
    );
    if (!draft.hasData) {
      await _clearDraft(scope);
      return;
    }
    try {
      final saved = await _api.upsertDraftOrder(
        sessionId: session.sessionId,
        storeId: scope.storeId,
        orderType: scope.orderType,
        groupOrderId: scope.groupOrderId,
        fulfillmentType: _fulfillmentType,
        notes: _notesController.text.trim(),
        items: items,
        delivery: delivery,
        version: _draftVersion,
      );
      if (saved != null) {
        _draftVersion = saved.version;
        _latestDraft = saved;
      }
    } on DraftConflictException catch (err) {
      await _handleDraftConflict(err.latest);
    } catch (_) {}
  }

  DraftOrderDelivery? _buildDraftDelivery() {
    final addressText = _deliveryAddressController.text.trim();
    final instructions = _deliveryInstructionsController.text.trim();
    if (addressText.isEmpty &&
        instructions.isEmpty &&
        _deliveryLatLng == null &&
        _deliveryAddress == null) {
      return null;
    }
    return DraftOrderDelivery(
      addressText: addressText,
      instructions: instructions,
      dropoffLatLng: _deliveryLatLng,
      dropoffAddress: _deliveryAddress,
    );
  }

  Future<void> _clearDraft(_DraftScope scope) async {
    final session = _session;
    if (session == null) return;
    try {
      await _api.clearDraftOrder(
        sessionId: session.sessionId,
        storeId: scope.storeId,
        orderType: scope.orderType,
        groupOrderId: scope.groupOrderId,
      );
    } catch (_) {}
    _draftVersion = 0;
    _latestDraft = null;
    _draftPrompted = false;
  }

  Future<void> _loadDraftIfAvailable({bool forcePrompt = false}) async {
    final session = _session;
    if (session == null || _menu == null) return;
    final scope = _currentDraftScope();
    if (scope == null) return;
    final scopeKey = scope.key;
    if (_draftScopeKey != scopeKey) {
      _draftScopeKey = scopeKey;
      _draftPrompted = false;
      _draftVersion = 0;
      _latestDraft = null;
    }
    final draft = await _api.fetchDraftOrder(
      sessionId: session.sessionId,
      storeId: scope.storeId,
      orderType: scope.orderType,
      groupOrderId: scope.groupOrderId,
    );
    if (draft == null || !draft.hasData) {
      return;
    }
    _latestDraft = draft;
    _draftVersion = draft.version;
    if (!forcePrompt && _draftPrompted) return;
    if (_hasLocalDraftData()) return;
    _draftPrompted = true;
    final shouldApply = await _promptResumeDraft(draft);
    if (!mounted || !shouldApply) return;
    _applyDraft(draft);
  }

  Future<void> _handleDraftConflict(DraftOrder? latest) async {
    if (!mounted) return;
    if (latest == null) {
      _draftVersion = 0;
      return;
    }
    final useLatest = await _promptDraftConflict(latest);
    if (!mounted) return;
    if (useLatest) {
      _applyDraft(latest);
    } else {
      _draftVersion = latest.version;
      final scope = _currentDraftScope();
      if (scope != null) {
        await _saveDraft(scope);
      }
    }
  }

  Future<bool> _promptResumeDraft(DraftOrder draft) async {
    final itemCount = DraftOrderLogic.itemCount(draft);
    final total = DraftOrderLogic.totalCents(draft);
    final totalLabel = '\$${(total / 100).toStringAsFixed(2)}';
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Resume your cart?'),
            content: Text('You have $itemCount item(s) saved ($totalLabel).'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No thanks'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Resume'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _promptDraftConflict(DraftOrder latest) async {
    final itemCount = DraftOrderLogic.itemCount(latest);
    final total = DraftOrderLogic.totalCents(latest);
    final totalLabel = '\$${(total / 100).toStringAsFixed(2)}';
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cart updated elsewhere'),
            content: Text(
              'Another device updated this cart ($itemCount item(s), $totalLabel).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep mine'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use latest'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _applyDraft(DraftOrder draft) {
    if (!mounted) return;
    _draftRestoring = true;
    final cart = DraftOrderLogic.cartFromDraft(draft, _menu);
    setState(() {
      _cart = cart;
      _notesController.text = draft.notes;
      if (draft.fulfillmentType.isNotEmpty) {
        _fulfillmentType = draft.fulfillmentType;
      }
      if (draft.delivery != null) {
        _deliveryAddressController.text = draft.delivery!.addressText;
        _deliveryInstructionsController.text = draft.delivery!.instructions;
        _deliveryLatLng = draft.delivery!.dropoffLatLng;
        _deliveryAddress = draft.delivery!.dropoffAddress;
      }
    });
    _cartSheetSetState?.call(() {});
    if (_isDeliverySelected && _deliveryEnabled) {
      _maybePrewarmDelivery();
    }
    _draftRestoring = false;
  }
}
