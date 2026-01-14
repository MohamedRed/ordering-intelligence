part of 'mini_app_screen.dart';

mixin MiniAppStateStore
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateChatState,
        MiniAppStateMenu,
        MiniAppStateIdentity,
        MiniAppStateDelivery {
  Future<void> _selectStore(StoreChoice store) async {
    final session = _session;
    if (session == null) {
      return;
    }
    setState(() {
      _menu = null;
      _menuError = null;
      _loadingMenu = true;
      _categories = [];
      _activeCategory = '';
      _selectedProduct = null;
      _chatMessages.clear();
      _cart = [];
      _orderConfirmation = null;
      _groupOrder = null;
      _groupOrderParticipantId = null;
      _groupOrderSelectedParticipantId = null;
      _groupOrderError = null;
      _searchResults = [];
      _searchError = null;
      _searchController.clear();
      _notesController.clear();
      _resetDeliveryDraft();
    });
    try {
      await _api.selectStore(
        sessionId: session.sessionId,
        storeId: store.storeId,
      );
      await _refreshDeliverySettings(store.storeId, fallback: store);
      if (!mounted) {
        return;
      }
      final nextSession = SessionInfo(
        sessionId: session.sessionId,
        accountId: session.accountId,
        userId: session.userId,
        displayName: session.displayName,
        storeId: store.storeId,
        storeName: store.name,
        tenantId: store.tenantId,
        customerId: '',
        businessType: store.businessType,
        currency: store.currency,
        fuelDefaultPrepayCents: store.fuelDefaultPrepayCents,
        fuelPreauthCapCents: session.fuelPreauthCapCents,
        startGroupOrder: false,
        telegramBotUsername: session.telegramBotUsername,
      );
      setState(() {
        _session = nextSession;
        _orderUpdatesLabel = _platform.orderUpdatesLabel(nextSession);
        _customerProfile = null;
        _identityError = null;
      });
      await _loadIdentity();
      await _loadMenu(store.storeId);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _menuError = e.toString();
        _loadingMenu = false;
      });
    }
  }

  void _changeStore() {
    final session = _session;
    if (session == null) {
      return;
    }
    setState(() {
      final nextSession = SessionInfo(
        sessionId: session.sessionId,
        accountId: session.accountId,
        userId: session.userId,
        displayName: session.displayName,
        storeId: '',
        storeName: '',
        tenantId: '',
        customerId: '',
        businessType: '',
        currency: '',
        fuelDefaultPrepayCents: 0,
        fuelPreauthCapCents: session.fuelPreauthCapCents,
        startGroupOrder: false,
        telegramBotUsername: session.telegramBotUsername,
      );
      _session = nextSession;
      _orderUpdatesLabel = _platform.orderUpdatesLabel(nextSession);
      _customerProfile = null;
      _identityError = null;
      _menu = null;
      _menuError = null;
      _categories = [];
      _activeCategory = '';
      _selectedProduct = null;
      _chatMessages.clear();
      _cart = [];
      _orderConfirmation = null;
      _groupOrder = null;
      _groupOrderParticipantId = null;
      _groupOrderSelectedParticipantId = null;
      _groupOrderError = null;
      _searchResults = [];
      _searchError = null;
      _searchController.clear();
      _notesController.clear();
      _resetDeliveryDraft();
    });
  }
}
