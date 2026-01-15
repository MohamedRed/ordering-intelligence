part of 'mini_app_screen.dart';

mixin MiniAppStateReorders
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateMenu,
        MiniAppStateCart {
  void _applyRecommendedOrder(RecommendedOrder order) {
    final menu = _menu;
    if (menu == null) {
      return;
    }
    if (order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This reorder is not available yet.')),
      );
      return;
    }
    MiniAppScope.hapticsOf(context).impact(style: 'light');
    final result = ReorderLogic.apply(menu: menu, cart: _cart, order: order);
    final added = result.addedCount;
    final missing = result.missingCount;
    setState(() {
      _cart = result.cart;
    });
    _cartSheetSetState?.call(() {});
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $added item${added == 1 ? '' : 's'} to cart'),
        ),
      );
    }
    if (missing > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some items are no longer available.')),
      );
    }
  }
}
