part of 'mini_app_screen.dart';

mixin MiniAppStateRecommendations on State<MiniAppScreen>, MiniAppStateFields {
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
      setState(() {
        _recommendedOrders = orders;
        _recommendedOrdersLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recommendedOrders = [];
        _recommendedOrdersLoaded = true;
      });
    }
  }
}
