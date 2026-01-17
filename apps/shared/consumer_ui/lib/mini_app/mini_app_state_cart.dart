part of 'mini_app_screen.dart';

mixin MiniAppStateCart
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateOrder,
        MiniAppStateGroupOrdersItems {
  int get _cartItemCount =>
      CartLogic.itemCount(_cart);

  int get _cartTotalCents => CartLogic.totalCents(_cart);

  String _formatPrice(int cents) {
    final value = (cents / 100).toStringAsFixed(2);
    return '\$$value';
  }

  Future<void> _handleAdd(MenuItem item) async {
    if (item.modifierGroups.isEmpty) {
      _addToCart(item, const []);
      return;
    }
    final selections = await showDialog<List<ModifierSelection>>(
      context: context,
      builder: (_) => ModifierDialog(item: item),
    );
    if (!mounted || selections == null) {
      return;
    }
    _addToCart(item, selections);
  }

  void _addToCart(MenuItem item, List<ModifierSelection> selections) {
    final newItem = CartItem(item: item, quantity: 1, selections: selections);
    setState(() {
      _orderError = null;
      _cart = CartLogic.addItem(_cart, newItem);
    });
    _cartSheetSetState?.call(() {});
    _onDraftRelevantChange();
  }

  void _updateCartQuantity(CartItem item, int delta) {
    setState(() {
      _orderError = null;
      _cart = CartLogic.updateQuantity(_cart, item, delta);
    });
    _cartSheetSetState?.call(() {});
    _onDraftRelevantChange();
  }
}
