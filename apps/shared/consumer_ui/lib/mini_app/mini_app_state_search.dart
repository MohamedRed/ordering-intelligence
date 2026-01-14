part of 'mini_app_screen.dart';

mixin MiniAppStateSearch on State<MiniAppScreen>, MiniAppStateFields, MiniAppStateStore {
  void _onSearchChanged() {
    if (_storeSearchMode) {
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  Future<void> _performSearch() async {
    await _runStoreSearch(_searchController.text.trim());
  }

  Future<List<StoreChoice>> _searchStoresFromChat(String query) async {
    await _runStoreSearch(query);
    return _searchResults;
  }

  Future<void> _runStoreSearch(String query) async {
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _api.searchStores(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchError = e.toString();
        _searchResults = [];
        _searching = false;
      });
    }
  }

  Future<void> _loadRecommendedOrders() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      final orders = await _api.fetchRecommendedOrders(
        sessionId: session.sessionId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _recommendedOrders = orders);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _recommendedOrders = []);
    }
  }

  void _selectRecommendedOrder(RecommendedOrder order) {
    final choice = StoreChoice(
      name: order.storeName,
      storeId: order.storeId,
      tenantId: order.tenantId,
      businessType: order.businessType,
      logoUrl: order.logoUrl,
    );
    _selectStore(choice);
  }
}
