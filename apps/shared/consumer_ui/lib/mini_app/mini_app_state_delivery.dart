part of 'mini_app_screen.dart';

mixin MiniAppStateDelivery on State<MiniAppScreen>, MiniAppStateFields {
  final TextEditingController _deliveryAddressController =
      TextEditingController();
  final TextEditingController _deliveryInstructionsController =
      TextEditingController();

  Timer? _deliveryPrewarmDebounce;
  String _fulfillmentType = 'pickup';
  bool _deliveryEnabled = false;
  String _deliveryFleetMode = 'marketplace';
  bool _deliveryPrewarming = false;
  String? _deliveryError;
  int? _deliveryEtaMinutes;
  DeliveryLatLng? _deliveryLatLng;
  DeliveryAddress? _deliveryAddress;
  String _lastPrewarmQuery = '';

  bool get _isDeliverySelected => _fulfillmentType == 'delivery';

  String get _deliveryFleetLabel {
    final mode = _deliveryFleetMode.trim();
    if (mode.isEmpty) return 'Delivery';
    return mode.replaceAll('_', ' ');
  }

  void _toggleDelivery(bool enabled) async {
    setState(() {
      _fulfillmentType = enabled ? 'delivery' : 'pickup';
      _deliveryError = null;
    });
    _collapseContextAfterSelection();
    _cartSheetSetState?.call(() {});
    if (!enabled) {
      _deliveryPrewarmDebounce?.cancel();
    } else {
      if (_deliveryAddressController.text.trim().isEmpty) {
        await _promptForDeliveryAddress();
      }
      _maybePrewarmDelivery();
    }
  }

  Future<void> _promptForDeliveryAddress() async {
    if (!mounted) return;
    final controller = TextEditingController(
      text: _deliveryAddressController.text,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delivery address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Enter delivery address',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }
    _deliveryAddressController.text = trimmed;
    _onDeliveryAddressChanged(trimmed);
  }

  void _maybePrewarmDelivery() {
    final query = _deliveryAddressController.text.trim();
    if (query.isEmpty) return;
    _scheduleDeliveryPrewarm(query);
  }

  void _onDeliveryAddressChanged(String value) {
    final query = value.trim();
    if (!_isDeliverySelected) return;
    if (query.isEmpty) {
      setState(() {
        _deliveryEtaMinutes = null;
        _deliveryLatLng = null;
        _deliveryAddress = null;
        _deliveryError = null;
      });
      _cartSheetSetState?.call(() {});
      return;
    }
    _scheduleDeliveryPrewarm(query);
  }

  void _scheduleDeliveryPrewarm(String query) {
    _deliveryPrewarmDebounce?.cancel();
    _deliveryPrewarmDebounce = Timer(const Duration(milliseconds: 700), () {
      _prewarmDelivery(query);
    });
  }

  Future<void> _prewarmDelivery(String query) async {
    final session = _session;
    if (session == null || session.storeId.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _deliveryPrewarming = true;
      _deliveryError = null;
    });
    _cartSheetSetState?.call(() {});
    _lastPrewarmQuery = query;
    try {
      final result = await _api.prewarmDelivery(
        sessionId: session.sessionId,
        storeId: session.storeId,
        dropoffAddressText: query,
        dropoffAddress: DeliveryAddress(formatted: query),
      );
      if (!mounted || _lastPrewarmQuery != query) return;
      setState(() {
        _deliveryPrewarming = false;
        _deliveryEtaMinutes = result?.etaMinutes;
        _deliveryLatLng = result?.dropoffLatLng;
        _deliveryAddress = result?.dropoffAddress;
      });
      _cartSheetSetState?.call(() {});
    } catch (e) {
      if (!mounted || _lastPrewarmQuery != query) return;
      setState(() {
        _deliveryPrewarming = false;
        _deliveryError = e.toString();
      });
      _cartSheetSetState?.call(() {});
    }
  }

  Future<void> _refreshDeliverySettings(
    String storeId, {
    StoreChoice? fallback,
  }) async {
    if (storeId.isEmpty) return;
    StoreChoice? choice = fallback;
    try {
      choice = await _api.fetchStoreDetails(storeId) ?? choice;
    } catch (_) {
      // ignore; fallback handles missing store metadata
    }
    if (choice == null || !mounted) return;
    setState(() {
      _deliveryEnabled = choice!.deliveryEnabled;
      _deliveryFleetMode = choice.deliveryFleetMode.isNotEmpty
          ? choice.deliveryFleetMode
          : 'marketplace';
      if (!_deliveryEnabled) {
        _fulfillmentType = 'pickup';
        _resetDeliveryDraft();
      }
    });
    _cartSheetSetState?.call(() {});
  }

  DeliveryDraft? _buildDeliveryDraft() {
    if (!_isDeliverySelected || !_deliveryEnabled) return null;
    final addressText = _deliveryAddressController.text.trim();
    final address =
        _deliveryAddress ??
        (addressText.isEmpty ? null : DeliveryAddress(formatted: addressText));
    if (address == null && _deliveryLatLng == null) {
      return null;
    }
    final instructions = _deliveryInstructionsController.text.trim();
    final fleetMode = _deliveryFleetMode.trim().isEmpty
        ? 'marketplace'
        : _deliveryFleetMode.trim();
    return DeliveryDraft(
      fleetMode: fleetMode,
      dropoffLatLng: _deliveryLatLng,
      dropoffAddress: address,
      instructions: instructions,
    );
  }

  void _resetDeliveryDraft() {
    _deliveryAddressController.clear();
    _deliveryInstructionsController.clear();
    _deliveryLatLng = null;
    _deliveryAddress = null;
    _deliveryEtaMinutes = null;
    _deliveryError = null;
    _deliveryPrewarming = false;
    _lastPrewarmQuery = '';
  }

  Widget? _buildDeliverySection() {
    if (_session == null || _session!.storeId.isEmpty) return null;
    return DeliveryOptionsSection(
      enabled: _deliveryEnabled,
      isDelivery: _isDeliverySelected,
      onToggle: _toggleDelivery,
      addressController: _deliveryAddressController,
      instructionsController: _deliveryInstructionsController,
      onAddressChanged: _onDeliveryAddressChanged,
      etaMinutes: _deliveryEtaMinutes,
      prewarming: _deliveryPrewarming,
      error: _deliveryError,
      fleetModeLabel: _deliveryFleetLabel,
    );
  }

  @override
  void dispose() {
    _deliveryPrewarmDebounce?.cancel();
    _deliveryAddressController.dispose();
    _deliveryInstructionsController.dispose();
    super.dispose();
  }
}
