part of 'mini_app_screen.dart';

mixin MiniAppStateGroupOrdersHydrate
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateIdentity {
  Future<void> _hydrateGroupOrderStore(String storeId) async {
    if (storeId.isEmpty) return;
    final session = _session;
    if (session == null || session.storeId == storeId) {
      await _loadMenu(storeId);
      await _loadStoreRecommendations(storeId);
      return;
    }
    final refreshed = await _platform.refreshSessionForStore(
      session: session,
      storeId: storeId,
      locale: _locale,
    );
    if (!mounted) return;
    setState(() {
      _session = refreshed;
      _orderUpdatesLabel = _platform.orderUpdatesLabel(refreshed);
    });
    await _loadIdentity();
    await _loadMenu(storeId);
    await _loadStoreRecommendations(storeId);
  }
}
